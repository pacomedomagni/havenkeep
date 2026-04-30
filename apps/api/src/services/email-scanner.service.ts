import { google } from 'googleapis';
import axios from 'axios';
import { pool } from '../db';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';
import { config } from '../config';
import { EmailScan } from '../types/database.types';
import { addMonthsSafe } from '../utils/dates';
import {
  decryptToken,
  encryptToken,
  isOAuthEncryptionConfigured,
} from '../utils/oauth-encryption';

/**
 * Mask PII (credit cards, SSNs, phone numbers) before sending text to external APIs.
 */
function maskPII(text: string): string {
  return text
    // Credit card numbers (13-19 digits, possibly with spaces/dashes)
    .replace(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{1,7}\b/g, '[CARD REDACTED]')
    // SSN
    .replace(/\b\d{3}-\d{2}-\d{4}\b/g, '[SSN REDACTED]')
    // Phone numbers
    .replace(/\b(\+?1?[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/g, '[PHONE REDACTED]');
}

/**
 * Strip HTML tags from email body content, collapsing whitespace.
 * Removes <style> and <script> blocks entirely before stripping tags
 * so their content doesn't end up as garbled text in the AI prompt.
 */
function stripHtmlTags(html: string): string {
  return html
    // Remove <style>...</style> and <script>...</script> blocks
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, ' ')
    // Replace <br>, <p>, <div>, <tr> with newlines to preserve structure
    .replace(/<(br|p|div|tr)[^>]*>/gi, '\n')
    // Strip remaining tags
    .replace(/<[^>]+>/g, ' ')
    // Decode common HTML entities
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    // Collapse excessive whitespace/newlines
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

interface ExtractedReceipt {
  productName: string;
  brand?: string;
  price?: number;
  purchaseDate?: string;
  warrantyPeriod?: number;
  store?: string;
  modelNumber?: string;
  serialNumber?: string;
  category?: string;
  emailSubject?: string;
  emailDate?: string;
  // Sender email used for trusted-domain gating + review-queue rows.
  senderAddress?: string;
  senderDomain?: string;
  // Confidence score (0..1) returned by OpenAI; defaults to 0 when missing.
  confidence?: number;
  // S-ME-07: did the source-mail's Authentication-Results header report
  // dkim=pass? Used to gate auto-import — without DKIM=pass we route to
  // the review queue regardless of trusted-domain match.
  dkimPassed?: boolean;
}

export type EmailScannerProvider = 'gmail' | 'outlook';

/**
 * Trusted retailer domains. Mail received FROM these domains is allowed to
 * auto-create items when OpenAI returns a high-confidence extraction.
 * Anything else is parked in the review queue. This is intentionally tight —
 * it is an allowlist, not a tag list. Keep additions deliberate.
 */
const TRUSTED_RETAILER_DOMAINS: ReadonlySet<string> = new Set([
  'amazon.com',
  'bestbuy.com',
  'costco.com',
  'frys.com',
  'homedepot.com',
  'lowes.com',
  'samsclub.com',
  'target.com',
  'walmart.com',
  'wayfair.com',
]);

/** Confidence threshold (inclusive) at which a trusted-domain match auto-creates. */
const AUTO_CREATE_CONFIDENCE_THRESHOLD = 0.85;

/** Approx Google access-token lifetime; cache slightly under to avoid edge expiry. */
const ACCESS_TOKEN_TTL_SECONDS = 50 * 60;

const GMAIL_SCOPE = 'https://www.googleapis.com/auth/gmail.readonly';
const OUTLOOK_SCOPE = 'offline_access https://graph.microsoft.com/Mail.Read';

// F064: hard timeout for axios (Outlook list + OpenAI extract) so a hung
// upstream can't park the scan worker indefinitely.
const HTTP_TIMEOUT_MS = 30_000;

// F063: per-user-day OpenAI cost cap (USD micro-cents). 100 cents/day per
// user limits worst-case cost from a runaway scanner run. Tunable via env.
const OPENAI_DAILY_CAP_MICROS = Math.max(
  1,
  Number(process.env.OPENAI_DAILY_CAP_MICROS ?? 100_000_000),
);

// F063: max OpenAI retries on 429/5xx before we give up on a single email.
const OPENAI_MAX_ATTEMPTS = 3;

interface OAuthTokenSet {
  accessToken: string;
  refreshToken?: string;
  expiresInSeconds: number;
  scope?: string;
}

interface OAuthIntegrationRow {
  id: string;
  user_id: string;
  provider: EmailScannerProvider;
  provider_email: string;
  refresh_token_ciphertext: string;
  refresh_token_iv: string;
  refresh_token_tag: string;
  access_token_ciphertext: string | null;
  access_token_iv: string | null;
  access_token_tag: string | null;
  access_token_expires_at: Date | null;
  granted_scope: string;
  revoked_at: Date | null;
}

export interface ReviewQueueRow {
  id: string;
  user_id: string;
  email_scan_id: string;
  sender_address: string;
  sender_domain: string;
  subject: string | null;
  suggested_item: ExtractedReceipt;
  confidence_score: string | number;
  state: 'pending' | 'approved' | 'rejected';
  rejection_reason: string | null;
  rejected_by_pattern: string | null;
  reviewed_at: Date | null;
  applied_item_id: string | null;
  created_at: Date;
}

function extractDomain(senderAddress: string | undefined | null): string {
  if (!senderAddress) return '';
  // The Gmail "From" header is often `"Display Name" <addr@host>`.
  const match = senderAddress.match(/<([^>]+)>/);
  const cleanAddr = (match ? match[1] : senderAddress).trim().toLowerCase();
  const at = cleanAddr.lastIndexOf('@');
  if (at < 0) return '';
  const domain = cleanAddr.slice(at + 1);
  // Treat sub-domains as the registrable domain for allowlisting purposes.
  // This is a coarse heuristic — fine for retailers in TRUSTED_RETAILER_DOMAINS.
  const parts = domain.split('.');
  if (parts.length >= 2) {
    return parts.slice(-2).join('.');
  }
  return domain;
}

function senderEmail(senderHeader: string | undefined | null): string {
  if (!senderHeader) return '';
  const match = senderHeader.match(/<([^>]+)>/);
  return (match ? match[1] : senderHeader).trim().toLowerCase();
}

export class EmailScannerService {
  /**
   * Initiate an email scan from an OAuth authorization `code`.
   *
   * Server-side flow:
   *   1. Exchange `code` + `redirect_uri` with the provider for access +
   *      refresh tokens.
   *   2. Verify the resulting account email matches the authenticated user.
   *   3. Encrypt the refresh token (AES-256-GCM) and persist in
   *      `user_oauth_integrations`. Cache the access token in the same row.
   *   4. Run the scan in the background using the just-minted access token.
   *
   * The mobile/web client never sends an access token to this endpoint.
   */
  static async initiateScan(
    userId: string,
    provider: EmailScannerProvider,
    code: string,
    redirectUri: string,
    options: {
      dateRangeStart?: string;
      dateRangeEnd?: string;
    } = {}
  ): Promise<EmailScan> {
    if (!isOAuthEncryptionConfigured()) {
      throw new AppError('OAuth integration not configured', 503);
    }

    // Exchange code → tokens at the provider, then verify ownership.
    const tokenSet = await this.exchangeAuthorizationCode(provider, code, redirectUri);

    // F060: verify the granted scope actually contains what we need. Some
    // OAuth flows let the user uncheck individual scopes on the consent
    // screen; without this guard we'd carry the integration forward and
    // fail mysteriously on the first list call.
    this.assertGrantedScope(provider, tokenSet.scope);

    const providerEmail = await this.fetchProviderEmail(provider, tokenSet.accessToken);
    await this.assertProviderEmailMatchesUser(userId, providerEmail);

    if (!tokenSet.refreshToken) {
      // Without a refresh token we cannot run scans on a future schedule.
      // Force the client to re-prompt with the consent screen so Google/MS
      // returns a refresh token.
      throw new AppError(
        'OAuth provider did not return a refresh token. Re-grant access with offline scope.',
        400,
      );
    }

    await this.upsertIntegration(userId, provider, providerEmail, tokenSet);

    const client = await pool.connect();
    let scan: EmailScan;
    try {
      await client.query('BEGIN');

      const scanResult = await client.query(
        `INSERT INTO email_scans (user_id, provider, provider_email, status, date_range_start, date_range_end)
         VALUES ($1, $2, $3, 'pending', $4, $5)
         RETURNING *`,
        [
          userId,
          provider,
          providerEmail,
          options.dateRangeStart || null,
          options.dateRangeEnd || null,
        ]
      );
      scan = scanResult.rows[0];

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, userId, provider }, 'Error initiating email scan');
      throw error;
    } finally {
      client.release();
    }

    // Run the scan in the background using the freshly minted access token.
    //
    // C11: capture the timer handle so we can clearTimeout it on the
    // success path. Without this, a 5-min closure (capturing the
    // AbortController + scan id + reject callback) survives every
    // successful scan for 5 minutes — on a busy deploy hundreds of
    // these accumulate and hold the event loop open at shutdown.
    const abortController = new AbortController();
    let timeoutHandle: NodeJS.Timeout | undefined;
    const scanPromise = this.performScan(
      scan.id,
      userId,
      provider,
      tokenSet.accessToken,
      options,
      abortController.signal,
    );
    const timeoutPromise = new Promise<void>((_, reject) => {
      timeoutHandle = setTimeout(() => {
        abortController.abort();
        reject(new Error('Email scan timed out after 5 minutes'));
      }, 5 * 60 * 1000);
    });

    Promise.race([scanPromise, timeoutPromise])
      .catch(async (error) => {
        logger.error(
          { errorMessage: (error as Error).message, scanId: scan.id },
          'Background email scan failed',
        );
        try {
          await pool.query(
            `UPDATE email_scans SET status = 'failed', error_message = $2, completed_at = NOW() WHERE id = $1 AND status != 'completed'`,
            [scan.id, (error as Error).message || 'Unknown error'],
          );
        } catch (updateError) {
          logger.error({ updateError, scanId: scan.id }, 'Failed to update scan status after error');
        }
      })
      .finally(() => {
        if (timeoutHandle) clearTimeout(timeoutHandle);
      });

    return scan;
  }

  /**
   * Revoke a stored OAuth integration. Called from the user-delete pipeline
   * so deleted users no longer have refresh tokens lingering server-side.
   * Soft-marks the row with revoked_at; the row itself is kept for audit.
   */
  static async revokeIntegration(
    userId: string,
    provider?: EmailScannerProvider,
  ): Promise<void> {
    if (provider) {
      await pool.query(
        `UPDATE user_oauth_integrations
            SET revoked_at = NOW(),
                access_token_ciphertext = NULL,
                access_token_iv = NULL,
                access_token_tag = NULL,
                access_token_expires_at = NULL
          WHERE user_id = $1 AND provider = $2 AND revoked_at IS NULL`,
        [userId, provider],
      );
    } else {
      await pool.query(
        `UPDATE user_oauth_integrations
            SET revoked_at = NOW(),
                access_token_ciphertext = NULL,
                access_token_iv = NULL,
                access_token_tag = NULL,
                access_token_expires_at = NULL
          WHERE user_id = $1 AND revoked_at IS NULL`,
        [userId],
      );
    }
  }

  /**
   * Exchange the OAuth `code` with the provider for an access + refresh token.
   */
  private static async exchangeAuthorizationCode(
    provider: EmailScannerProvider,
    code: string,
    redirectUri: string,
  ): Promise<OAuthTokenSet> {
    if (provider === 'gmail') {
      const clientId = config.google.clientId;
      const clientSecret = config.google.clientSecret;
      if (!clientId || !clientSecret) {
        throw new AppError('Google OAuth client credentials not configured', 503);
      }

      const params = new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
      });

      const resp = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString(),
      });

      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        logger.warn(
          { status: resp.status, body: text.slice(0, 200) },
          'Google OAuth code exchange failed',
        );
        throw new AppError('Failed to exchange Google OAuth code', 401);
      }

      const json = (await resp.json()) as {
        access_token?: string;
        refresh_token?: string;
        expires_in?: number;
        scope?: string;
      };

      if (!json.access_token) {
        throw new AppError('Google OAuth response missing access_token', 502);
      }

      return {
        accessToken: json.access_token,
        refreshToken: json.refresh_token,
        expiresInSeconds: json.expires_in ?? ACCESS_TOKEN_TTL_SECONDS,
        scope: json.scope,
      };
    }

    // Outlook / Microsoft Graph
    const clientId = config.microsoft.clientId;
    const clientSecret = config.microsoft.clientSecret;
    const tenant = config.microsoft.tenant;
    if (!clientId || !clientSecret) {
      throw new AppError('Microsoft OAuth client credentials not configured', 503);
    }

    const params = new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
      scope: OUTLOOK_SCOPE,
    });

    const resp = await fetch(
      `https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString(),
      },
    );

    if (!resp.ok) {
      const text = await resp.text().catch(() => '');
      logger.warn(
        { status: resp.status, body: text.slice(0, 200) },
        'Microsoft OAuth code exchange failed',
      );
      throw new AppError('Failed to exchange Microsoft OAuth code', 401);
    }

    const json = (await resp.json()) as {
      access_token?: string;
      refresh_token?: string;
      expires_in?: number;
      scope?: string;
    };

    if (!json.access_token) {
      throw new AppError('Microsoft OAuth response missing access_token', 502);
    }

    return {
      accessToken: json.access_token,
      refreshToken: json.refresh_token,
      expiresInSeconds: json.expires_in ?? ACCESS_TOKEN_TTL_SECONDS,
      scope: json.scope,
    };
  }

  /**
   * Refresh a stored access token using the encrypted refresh token. Updates
   * the integration row's cached access token + expiry.
   */
  private static async refreshAccessTokenForIntegration(
    integration: OAuthIntegrationRow,
  ): Promise<string> {
    const refreshToken = decryptToken({
      ciphertext: integration.refresh_token_ciphertext,
      iv: integration.refresh_token_iv,
      tag: integration.refresh_token_tag,
    });

    let json: { access_token?: string; expires_in?: number };

    if (integration.provider === 'gmail') {
      const clientId = config.google.clientId;
      const clientSecret = config.google.clientSecret;
      if (!clientId || !clientSecret) {
        throw new AppError('Google OAuth client credentials not configured', 503);
      }
      const params = new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
      });
      const resp = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString(),
      });
      if (!resp.ok) {
        throw new AppError('Failed to refresh Google access token', 401);
      }
      json = (await resp.json()) as { access_token?: string; expires_in?: number };
    } else {
      const clientId = config.microsoft.clientId;
      const clientSecret = config.microsoft.clientSecret;
      const tenant = config.microsoft.tenant;
      if (!clientId || !clientSecret) {
        throw new AppError('Microsoft OAuth client credentials not configured', 503);
      }
      const params = new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
        scope: OUTLOOK_SCOPE,
      });
      const resp = await fetch(
        `https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: params.toString(),
        },
      );
      if (!resp.ok) {
        throw new AppError('Failed to refresh Microsoft access token', 401);
      }
      json = (await resp.json()) as { access_token?: string; expires_in?: number };
    }

    if (!json.access_token) {
      throw new AppError('OAuth refresh response missing access_token', 502);
    }

    const ttl = Math.min(json.expires_in ?? ACCESS_TOKEN_TTL_SECONDS, ACCESS_TOKEN_TTL_SECONDS);
    const cached = encryptToken(json.access_token);
    const expiresAt = new Date(Date.now() + ttl * 1000);

    await pool.query(
      `UPDATE user_oauth_integrations
          SET access_token_ciphertext = $2,
              access_token_iv = $3,
              access_token_tag = $4,
              access_token_expires_at = $5,
              updated_at = NOW()
        WHERE id = $1`,
      [integration.id, cached.ciphertext, cached.iv, cached.tag, expiresAt],
    );

    return json.access_token;
  }

  /**
   * Retrieve a usable access token for an existing integration. Returns the
   * cached token if it has time left, otherwise refreshes via the provider.
   * Exposed primarily for future scheduled scans; the route uses the freshly
   * minted token from initiateScan instead.
   */
  static async getAccessToken(
    userId: string,
    provider: EmailScannerProvider,
  ): Promise<string> {
    if (!isOAuthEncryptionConfigured()) {
      throw new AppError('OAuth integration not configured', 503);
    }

    const result = await pool.query<OAuthIntegrationRow>(
      `SELECT * FROM user_oauth_integrations
        WHERE user_id = $1 AND provider = $2 AND revoked_at IS NULL
        ORDER BY updated_at DESC
        LIMIT 1`,
      [userId, provider],
    );
    const integration = result.rows[0];
    if (!integration) {
      throw new AppError('OAuth integration not found for user', 404);
    }

    const now = Date.now();
    const expiresAt = integration.access_token_expires_at?.getTime() ?? 0;
    if (
      integration.access_token_ciphertext &&
      integration.access_token_iv &&
      integration.access_token_tag &&
      expiresAt > now + 60_000
    ) {
      return decryptToken({
        ciphertext: integration.access_token_ciphertext,
        iv: integration.access_token_iv,
        tag: integration.access_token_tag,
      });
    }

    return this.refreshAccessTokenForIntegration(integration);
  }

  private static async upsertIntegration(
    userId: string,
    provider: EmailScannerProvider,
    providerEmail: string,
    tokenSet: OAuthTokenSet,
  ): Promise<void> {
    if (!tokenSet.refreshToken) {
      throw new AppError('Provider did not return a refresh token', 400);
    }

    const refresh = encryptToken(tokenSet.refreshToken);
    const access = encryptToken(tokenSet.accessToken);
    const ttl = Math.min(tokenSet.expiresInSeconds, ACCESS_TOKEN_TTL_SECONDS);
    const accessExpiresAt = new Date(Date.now() + ttl * 1000);
    const grantedScope = tokenSet.scope || (provider === 'gmail' ? GMAIL_SCOPE : OUTLOOK_SCOPE);

    await pool.query(
      `INSERT INTO user_oauth_integrations (
         user_id, provider, provider_email,
         refresh_token_ciphertext, refresh_token_iv, refresh_token_tag,
         access_token_ciphertext, access_token_iv, access_token_tag,
         access_token_expires_at, granted_scope, revoked_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NULL)
       ON CONFLICT (user_id, provider, provider_email)
       DO UPDATE SET
         refresh_token_ciphertext = EXCLUDED.refresh_token_ciphertext,
         refresh_token_iv         = EXCLUDED.refresh_token_iv,
         refresh_token_tag        = EXCLUDED.refresh_token_tag,
         access_token_ciphertext  = EXCLUDED.access_token_ciphertext,
         access_token_iv          = EXCLUDED.access_token_iv,
         access_token_tag         = EXCLUDED.access_token_tag,
         access_token_expires_at  = EXCLUDED.access_token_expires_at,
         granted_scope            = EXCLUDED.granted_scope,
         revoked_at               = NULL,
         updated_at               = NOW()`,
      [
        userId,
        provider,
        providerEmail,
        refresh.ciphertext,
        refresh.iv,
        refresh.tag,
        access.ciphertext,
        access.iv,
        access.tag,
        accessExpiresAt,
        grantedScope,
      ],
    );
  }

  private static async fetchProviderEmail(
    provider: EmailScannerProvider,
    accessToken: string,
  ): Promise<string> {
    if (provider === 'gmail') {
      const resp = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!resp.ok) {
        throw new AppError('Unable to verify Google access token', 401);
      }
      const info = (await resp.json()) as { email?: string };
      const email = info.email?.toLowerCase();
      if (!email) {
        throw new AppError('Google did not return an account email', 502);
      }
      return email;
    }

    const resp = await fetch('https://graph.microsoft.com/v1.0/me', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!resp.ok) {
      throw new AppError('Unable to verify Microsoft access token', 401);
    }
    const info = (await resp.json()) as { mail?: string; userPrincipalName?: string };
    const email = (info.mail || info.userPrincipalName || '').toLowerCase();
    if (!email) {
      throw new AppError('Microsoft did not return an account email', 502);
    }
    return email;
  }

  /**
   * F060: enforce that the OAuth provider actually granted the scope we
   * asked for. Token-exchange responses include `scope` as a
   * space-separated list (Gmail) or with offline_access prefix (Outlook).
   */
  private static assertGrantedScope(
    provider: EmailScannerProvider,
    grantedScope: string | undefined,
  ): void {
    const required = provider === 'gmail' ? GMAIL_SCOPE : 'https://graph.microsoft.com/Mail.Read';
    const granted = (grantedScope || '').split(/\s+/).filter(Boolean);
    if (!granted.includes(required)) {
      throw new AppError(
        `OAuth grant is missing required scope "${required}". Re-grant access with the requested permission.`,
        403,
      );
    }
  }

  private static async assertProviderEmailMatchesUser(
    userId: string,
    providerEmail: string,
  ): Promise<void> {
    const userRes = await pool.query(
      'SELECT email FROM users WHERE id = $1 AND deleted_at IS NULL',
      [userId],
    );
    const havenkeepEmail = userRes.rows[0]?.email?.toLowerCase();
    if (!havenkeepEmail) {
      throw new AppError('User not found', 404);
    }
    if (providerEmail !== havenkeepEmail) {
      logger.warn(
        { userId, providerEmail, havenkeepEmail },
        'Email scanner: OAuth account email does not match authenticated user',
      );
      throw new AppError('The OAuth account does not belong to this HavenKeep user', 403);
    }
  }

  /**
   * Perform the actual email scanning (runs in background)
   */
  private static async performScan(
    scanId: string,
    userId: string,
    provider: EmailScannerProvider,
    accessToken: string,
    options: {
      dateRangeStart?: string;
      dateRangeEnd?: string;
    },
    signal?: AbortSignal
  ): Promise<void> {
    try {
      if (!config.openai?.apiKey) {
        await pool.query(
          `UPDATE email_scans
           SET status = 'failed',
               error_message = $2,
               completed_at = NOW()
           WHERE id = $1`,
          [scanId, 'OpenAI API key is not configured']
        );
        logger.warn({ scanId }, 'Email scan aborted: missing OpenAI API key');
        return;
      }

      // Update status to scanning
      await pool.query(
        `UPDATE email_scans SET status = 'scanning' WHERE id = $1`,
        [scanId]
      );

      // F063: short-circuit the scan if the user has already burned the
      // daily OpenAI budget. The dedup table still gets seeded so the
      // partial scan resumes cleanly tomorrow.
      if (!(await this.withinOpenAIBudget(userId, 'email_scan'))) {
        await pool.query(
          `UPDATE email_scans
              SET status = 'failed',
                  error_message = $2,
                  completed_at = NOW()
            WHERE id = $1`,
          [scanId, 'Daily OpenAI budget exhausted; try again tomorrow'],
        );
        logger.warn({ userId, scanId }, 'Email scan aborted: OpenAI daily budget exhausted');
        return;
      }

      const receipts: ExtractedReceipt[] =
        provider === 'gmail'
          ? await this.scanGmail(userId, scanId, accessToken, options, signal)
          : await this.scanOutlook(userId, scanId, accessToken, options, signal);

      logger.info({ scanId, receiptsFound: receipts.length }, 'Email scan completed');

      const relevantReceipts = receipts.filter((r) =>
        this.isRelevantPurchase(r.productName, r.category)
      );

      let importedCount = 0;
      let queuedCount = 0;
      let skippedDueToLimit = 0;

      for (const receipt of relevantReceipts) {
        const domain = receipt.senderDomain || '';
        const trusted = TRUSTED_RETAILER_DOMAINS.has(domain);
        const confidence = typeof receipt.confidence === 'number' ? receipt.confidence : 0;
        // S-ME-07: a trusted-domain match is necessary but not sufficient
        // for auto-import. The source mail must have DKIM=pass; otherwise
        // a spoofed `From: receipts@amazon.com` would slip through. Mail
        // that fails DKIM (or has no Authentication-Results header) goes
        // to the review queue where the user confirms each item.
        const autoCreate =
          trusted && confidence >= AUTO_CREATE_CONFIDENCE_THRESHOLD && receipt.dkimPassed === true;

        if (!autoCreate) {
          await this.enqueueReview(userId, scanId, receipt, confidence);
          queuedCount++;
          continue;
        }

        try {
          const created = await this.createItemFromReceipt(userId, receipt, scanId);
          if (created) {
            importedCount++;
          } else {
            skippedDueToLimit++;
          }
        } catch (error) {
          logger.warn({ error, productName: receipt.productName }, 'Failed to import receipt');
        }
      }

      const messages: string[] = [];
      if (skippedDueToLimit > 0) {
        messages.push(
          `${skippedDueToLimit} item${skippedDueToLimit === 1 ? '' : 's'} skipped — free plan limit reached. Upgrade to Premium to import all items.`,
        );
      }
      if (queuedCount > 0) {
        messages.push(
          `${queuedCount} item${queuedCount === 1 ? '' : 's'} pending your review.`,
        );
      }
      const completedMessage = messages.length ? messages.join(' ') : null;

      // H-D7 (audit): write success-path notes to the dedicated
      // completion_message column (mig 088) so monitoring queries
      // filtering on `error_message IS NOT NULL` for failed-scan rate
      // don't pick up these strings as noise.
      await pool.query(
        `UPDATE email_scans
         SET status = 'completed',
             emails_scanned = $2,
             receipts_found = $3,
             items_imported = $4,
             completion_message = $5,
             error_message = NULL,
             completed_at = NOW()
         WHERE id = $1`,
        [scanId, receipts.length, relevantReceipts.length, importedCount, completedMessage]
      );

      // F065: only count a scan as "completed" in user analytics when it
      // actually returned at least one inspected email. A no-op scan (zero
      // emails matched the trusted-sender filter) shouldn't tip the
      // engagement-flag UI to "you've scanned" — it never read anything.
      const scanCounted = receipts.length > 0;
      await pool.query(
        `UPDATE user_analytics
         SET email_scans_completed = email_scans_completed + CASE WHEN $3::bool THEN 1 ELSE 0 END,
             items_added_via_email = items_added_via_email + $2,
             has_scanned_email     = COALESCE(has_scanned_email, FALSE) OR $3::bool,
             updated_at = NOW()
         WHERE user_id = $1`,
        [userId, importedCount, scanCounted]
      );

      logger.info(
        { scanId, userId, importedCount, queuedCount },
        'Email scan completed successfully'
      );
    } catch (error) {
      logger.error({ error, scanId }, 'Error performing email scan');

      await pool.query(
        `UPDATE email_scans
         SET status = 'failed',
             error_message = $2,
             completed_at = NOW()
         WHERE id = $1`,
        [scanId, (error as Error).message]
      );
    }
  }

  /**
   * Scan Gmail for receipts. Only queries explicitly trusted retailer
   * senders — the legacy generic catch-all (`receipt OR purchase OR order`)
   * is removed because a spoofed sender + prompt injection in the email body
   * could otherwise auto-create items in the user's account.
   */
  private static async scanGmail(
    userId: string,
    scanId: string,
    accessToken: string,
    options: { dateRangeStart?: string; dateRangeEnd?: string },
    signal?: AbortSignal
  ): Promise<ExtractedReceipt[]> {
    const oauth2Client = new google.auth.OAuth2();
    oauth2Client.setCredentials({ access_token: accessToken });

    const gmail = google.gmail({ version: 'v1', auth: oauth2Client });

    const receipts: ExtractedReceipt[] = [];

    // Only mail FROM trusted retailer domains is scanned. Generic keyword
    // searches without a sender filter are intentionally not used (Ch09-FlowB-T-B7).
    const queries = Array.from(TRUSTED_RETAILER_DOMAINS).map(
      (domain) => `from:${domain} subject:(receipt OR order OR purchase)`,
    );

    // Build date query
    let dateQuery = '';
    if (options.dateRangeStart) {
      const startDate = new Date(options.dateRangeStart);
      dateQuery += ` after:${startDate.getFullYear()}/${startDate.getMonth() + 1}/${startDate.getDate()}`;
    }
    if (options.dateRangeEnd) {
      const endDate = new Date(options.dateRangeEnd);
      dateQuery += ` before:${endDate.getFullYear()}/${endDate.getMonth() + 1}/${endDate.getDate()}`;
    }

    for (const baseQuery of queries) {
      if (signal?.aborted) break;

      try {
        const query = baseQuery + dateQuery;

        const messagesResponse = await gmail.users.messages.list({
          userId: 'me',
          q: query,
          maxResults: 100,
        });

        const messages = messagesResponse.data.messages || [];

        for (const message of messages.slice(0, 50)) {
          if (signal?.aborted) break;

          // F067: skip messages we've already extracted from. Two of our
          // sender-domain queries can match the same Gmail message (e.g.
          // amazon.com order confirmation also contains "purchase" in the
          // subject) and without this guard we'd hit OpenAI twice and
          // double-bill the user's daily cap.
          const seenInsert = await pool.query(
            `INSERT INTO email_scanner_seen_messages
               (user_id, provider, provider_message_id, first_seen_scan_id)
             VALUES ($1, 'gmail', $2, $3)
             ON CONFLICT (user_id, provider, provider_message_id) DO NOTHING
             RETURNING user_id`,
            [userId, message.id!, scanId],
          );
          if (seenInsert.rowCount === 0) continue;

          // Limit to 50 per query
          try {
            const messageData = await gmail.users.messages.get({
              userId: 'me',
              id: message.id!,
              format: 'full',
            });

            const emailData = this.parseGmailMessage(messageData.data);
            const extracted = await this.extractReceiptData(emailData, signal, userId);

            if (extracted) {
              // S-ME-07: surface DKIM result so the import gate can read it.
              extracted.dkimPassed = this.dkimPassed(emailData.authResults);
              receipts.push(extracted);
            }
          } catch (error) {
            logger.warn({ error, messageId: message.id }, 'Failed to process Gmail message');
          }
        }
      } catch (error) {
        logger.warn({ error, query: baseQuery }, 'Failed to query Gmail');
      }
    }

    return receipts;
  }

  /**
   * Scan Outlook for receipts. Only queries trusted retailer senders — same
   * rationale as Gmail.
   */
  private static async scanOutlook(
    userId: string,
    scanId: string,
    accessToken: string,
    options: { dateRangeStart?: string; dateRangeEnd?: string },
    signal?: AbortSignal
  ): Promise<ExtractedReceipt[]> {
    const receipts: ExtractedReceipt[] = [];

    // Build a sender clause: from/emailAddress/address ENDSWITH each trusted domain.
    const fromClauses = Array.from(TRUSTED_RETAILER_DOMAINS).map(
      (domain) => `endswith(from/emailAddress/address, '@${domain}')`,
    );
    let filter = `(${fromClauses.join(' or ')})`;
    filter += ` and (contains(subject, 'receipt') or contains(subject, 'order') or contains(subject, 'purchase'))`;

    if (options.dateRangeStart) {
      filter += ` and receivedDateTime ge ${new Date(options.dateRangeStart).toISOString()}`;
    }
    if (options.dateRangeEnd) {
      filter += ` and receivedDateTime le ${new Date(options.dateRangeEnd).toISOString()}`;
    }

    try {
      // F064: 30s timeout so a hung Outlook tenant doesn't park the worker.
      const response = await axios.get('https://graph.microsoft.com/v1.0/me/messages', {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
        params: {
          $filter: filter,
          $top: 100,
          $select: 'subject,from,receivedDateTime,body',
        },
        signal,
        timeout: HTTP_TIMEOUT_MS,
      });

      const messages = response.data.value || [];

      for (const message of messages.slice(0, 50)) {
        if (signal?.aborted) break;

        // F067: dedup. Outlook's `id` is the closest analog to Gmail's
        // message id and is stable per-mailbox.
        if (message.id) {
          const seenInsert = await pool.query(
            `INSERT INTO email_scanner_seen_messages
               (user_id, provider, provider_message_id, first_seen_scan_id)
             VALUES ($1, 'outlook', $2, $3)
             ON CONFLICT (user_id, provider, provider_message_id) DO NOTHING
             RETURNING user_id`,
            [userId, message.id, scanId],
          );
          if (seenInsert.rowCount === 0) continue;
        }

        try {
          const fromAddress: string =
            message.from?.emailAddress?.address || '';
          const emailData = {
            subject: message.subject,
            from: fromAddress,
            date: message.receivedDateTime,
            body: message.body?.content || '',
          };

          const extracted = await this.extractReceiptData(emailData, signal);

          if (extracted) {
            receipts.push(extracted);
          }
        } catch (error) {
          logger.warn({ error, messageId: message.id }, 'Failed to process Outlook message');
        }
      }
    } catch (error) {
      logger.error({ error }, 'Failed to scan Outlook');
      throw error;
    }

    return receipts;
  }

  /**
   * Parse Gmail message to extract relevant data.
   *
   * S-ME-07: read the `Authentication-Results` header so the caller can
   * gate trusted-retailer auto-import on DKIM=pass. Without this check a
   * spoofed `From: receipts@amazon.com` lands on the trusted list and
   * auto-creates items. Gmail attaches its own Authentication-Results
   * header at receipt time; we just surface it.
   */
  private static parseGmailMessage(message: any): {
    subject: string;
    from: string;
    date: string;
    body: string;
    authResults: string;
  } {
    const headers = message.payload?.headers || [];
    const subject = headers.find((h: any) => h.name === 'Subject')?.value || '';
    const from = headers.find((h: any) => h.name === 'From')?.value || '';
    const date = headers.find((h: any) => h.name === 'Date')?.value || '';
    const authResults =
      headers.find((h: any) => h.name === 'Authentication-Results')?.value || '';

    // Extract body
    let body = '';
    if (message.payload?.body?.data) {
      body = Buffer.from(message.payload.body.data, 'base64').toString('utf-8');
    } else if (message.payload?.parts) {
      const textPart = message.payload.parts.find(
        (p: any) => p.mimeType === 'text/plain' || p.mimeType === 'text/html'
      );
      if (textPart?.body?.data) {
        body = Buffer.from(textPart.body.data, 'base64').toString('utf-8');
      }
    }

    return { subject, from, date, body, authResults };
  }

  /**
   * S-ME-07: parse the Authentication-Results header and return whether
   * DKIM passed. Examples of the header (RFC 8601):
   *   Authentication-Results: mx.google.com; dkim=pass header.i=@amazon.com; spf=pass smtp.mailfrom=...
   *   Authentication-Results: mx.google.com; dkim=fail (bad signature) header.i=@amazon.com
   * Treat anything other than `dkim=pass` as a failure (including
   * absent header — providers without DKIM aren't trusted-retailer
   * candidates).
   */
  private static dkimPassed(authResults: string | undefined | null): boolean {
    if (!authResults) return false;
    return /\bdkim=pass\b/i.test(authResults);
  }

  /**
   * F063: per-user-per-day OpenAI spend check. Returns true when the user
   * is still under the daily cap. Uses the openai_user_daily_cost view
   * landed in migration 067.
   */
  private static async withinOpenAIBudget(userId: string, feature: string): Promise<boolean> {
    const result = await pool.query<{ cost_micros: string }>(
      `SELECT COALESCE(SUM(cost_micros), 0)::text AS cost_micros
         FROM openai_user_daily_cost
        WHERE user_id = $1
          AND day = (NOW() AT TIME ZONE 'UTC')::date
          AND feature = $2`,
      [userId, feature],
    );
    const used = Number(result.rows[0]?.cost_micros ?? '0');
    return used < OPENAI_DAILY_CAP_MICROS;
  }

  /**
   * Extract receipt data using AI (OpenAI or Anthropic)
   *
   * PRIVACY NOTE: Email body content (up to 4000 chars) is sent to OpenAI for
   * receipt extraction. Ensure users are informed of this in the app's privacy
   * policy and terms of service. The access token is used only for email access
   * and is not stored.
   */
  /**
   * F063 closure: every OpenAI call from the email scanner now writes a row
   * to `openai_usage` so the per-user daily budget view reflects scanner
   * traffic too — not just the receipt route. `userId` is required so the
   * row is attributed to the right tenant; `feature='email_scan'` matches
   * the budget short-circuit upstream.
   *
   * Cost rates kept in sync with apps/api/src/routes/receipts.ts. If the
   * model price changes, update both sites.
   */
  private static readonly COST_PER_PROMPT_TOKEN_MICROS = 150n;
  private static readonly COST_PER_COMPLETION_TOKEN_MICROS = 600n;

  private static computeCostMicros(promptTokens: number, completionTokens: number): bigint {
    return (
      BigInt(Math.max(0, promptTokens)) * EmailScannerService.COST_PER_PROMPT_TOKEN_MICROS +
      BigInt(Math.max(0, completionTokens)) * EmailScannerService.COST_PER_COMPLETION_TOKEN_MICROS
    );
  }

  private static async recordScannerUsage(
    userId: string,
    promptTokens: number,
    completionTokens: number,
    totalTokens: number,
  ): Promise<void> {
    if (!userId || promptTokens + completionTokens === 0) return;
    try {
      await pool.query(
        `INSERT INTO openai_usage (
          user_id, feature, model, prompt_tokens, completion_tokens, total_tokens, cost_micros
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          userId,
          'email_scan',
          'gpt-4o-mini',
          promptTokens,
          completionTokens,
          totalTokens,
          EmailScannerService.computeCostMicros(promptTokens, completionTokens).toString(),
        ],
      );
    } catch (err) {
      // Never block the scan on a ledger write — the daily budget will
      // catch up on the next cron pass if Postgres flapped.
      logger.warn({ err, userId }, 'Failed to record email-scanner OpenAI usage');
    }
  }

  private static async extractReceiptData(emailData: {
    subject: string;
    from: string;
    date: string;
    body: string;
  }, signal?: AbortSignal, userId?: string): Promise<ExtractedReceipt | null> {
    const requestBody = {
      model: 'gpt-4o-mini', // Cheaper, faster model
      messages: [
        {
          role: 'system',
          content: `You are an AI that extracts purchase information from receipt emails.
Extract the following information and return as JSON:
- productName: Name of the product (if multiple, pick the most expensive/important appliance or electronic)
- brand: Brand name
- price: Total price (number only)
- purchaseDate: Date of purchase (ISO format)
- warrantyPeriod: Warranty period in months (default 12 if not specified)
- store: Store name
- modelNumber: Model number if available
- serialNumber: Serial number if available
- category: Best matching category (refrigerator, dishwasher, washer, dryer, oven_range, microwave, hvac, water_heater, tv, computer, other)
- confidence: Float 0..1 — how sure you are this is a real, parseable purchase receipt for a physical product (0 = not a receipt or unsure, 1 = definitely a receipt)

Only extract if this is clearly a purchase receipt for a physical product.
Focus on appliances, electronics, HVAC, and home systems.
Return null if this is not a product purchase receipt.`,
        },
        {
          role: 'user',
          content: `Subject: ${maskPII(emailData.subject)}
From: ${emailData.from}
Date: ${emailData.date}

Body:
${maskPII(stripHtmlTags(emailData.body).substring(0, 4000))}`,
        },
      ],
      response_format: { type: 'json_object' },
      temperature: 0,
    };
    const requestConfig = {
      headers: {
        'Authorization': `Bearer ${config.openai?.apiKey}`,
        'Content-Type': 'application/json',
      },
      signal,
      // F064: 30s ceiling — anything longer is a hung OpenAI request and
      // the per-scan budget is already counting against the user.
      timeout: HTTP_TIMEOUT_MS,
    } as const;

    // F063: retry on 429 / 5xx with exponential backoff. Permanent 4xx
    // (auth, malformed payload) bails immediately so we don't burn the
    // budget on a guaranteed-fail prompt.
    let response: any;
    let attempt = 0;
    let lastErr: any;
    while (attempt < OPENAI_MAX_ATTEMPTS) {
      attempt++;
      try {
        response = await axios.post('https://api.openai.com/v1/chat/completions', requestBody, requestConfig);
        lastErr = null;
        break;
      } catch (err: any) {
        lastErr = err;
        const status = err?.response?.status;
        const transient = status === 429 || (typeof status === 'number' && status >= 500);
        if (!transient || attempt >= OPENAI_MAX_ATTEMPTS) break;
        const backoff = 250 * Math.pow(2, attempt - 1);
        await new Promise((r) => setTimeout(r, backoff));
      }
    }
    if (lastErr || !response) {
      // Never log the full axios error — it may contain the Authorization
      // header. Surface only status + message.
      const safeError = {
        message: lastErr?.message,
        statusCode: lastErr?.response?.status,
        responseMessage: lastErr?.response?.data?.error?.message,
      };
      logger.warn({ error: safeError, subject: emailData.subject }, 'Failed to extract receipt data with AI');
      return null;
    }

    // F063: write the per-call usage to openai_usage. Do this regardless of
    // whether the JSON parse below succeeds — we still spent the tokens.
    if (userId) {
      const usage = response.data?.usage ?? {};
      await EmailScannerService.recordScannerUsage(
        userId,
        Number(usage.prompt_tokens ?? 0),
        Number(usage.completion_tokens ?? 0),
        Number(usage.total_tokens ?? 0),
      );
    }

    let extracted: any;
    try {
      extracted = JSON.parse(response.data.choices[0].message.content);
    } catch (parseError) {
      logger.warn({ parseError, subject: emailData.subject }, 'Failed to parse AI response as JSON');
      return null;
    }

    if (!extracted || !extracted.productName) {
      return null;
    }

    const confidence = typeof extracted.confidence === 'number'
      ? Math.max(0, Math.min(1, extracted.confidence))
      : 0;

    return {
      ...extracted,
      confidence,
      emailSubject: emailData.subject,
      emailDate: emailData.date,
      senderAddress: senderEmail(emailData.from),
      senderDomain: extractDomain(emailData.from),
    };
  }

  /**
   * Insert a receipt into the review queue. Used when the sender is not on
   * the trusted-retailer allowlist OR confidence is below the auto-create
   * threshold.
   */
  private static async enqueueReview(
    userId: string,
    scanId: string,
    receipt: ExtractedReceipt,
    confidence: number,
  ): Promise<void> {
    await pool.query(
      `INSERT INTO email_scanner_review_queue
        (user_id, email_scan_id, sender_address, sender_domain, subject,
         suggested_item, confidence_score, state)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, 'pending')`,
      [
        userId,
        scanId,
        receipt.senderAddress || '',
        receipt.senderDomain || '',
        receipt.emailSubject || null,
        JSON.stringify(receipt),
        confidence,
      ],
    );
  }

  /**
   * Check if product is relevant (appliances, electronics, HVAC)
   */
  private static isRelevantPurchase(productName: string, category?: string): boolean {
    const relevantCategories = [
      'refrigerator',
      'dishwasher',
      'washer',
      'dryer',
      'oven_range',
      'microwave',
      'hvac',
      'water_heater',
      'tv',
      'computer',
      'garbage_disposal',
      'range_hood',
      'furnace',
    ];

    if (category && relevantCategories.includes(category)) {
      return true;
    }

    // Check product name for keywords
    const keywords = [
      'refrigerator',
      'fridge',
      'dishwasher',
      'washer',
      'dryer',
      'oven',
      'range',
      'microwave',
      'hvac',
      'air conditioner',
      'furnace',
      'water heater',
      'television',
      'tv',
      'laptop',
      'computer',
      'disposal',
      'hood',
    ];

    const lowerName = productName.toLowerCase();
    return keywords.some((keyword) => lowerName.includes(keyword));
  }

  /**
   * Create item from extracted receipt.
   * Returns true if item was created, false if skipped due to free plan limit.
   * If `targetClient` is supplied, the caller owns the transaction (used by
   * the review-queue approve handler so the queue + item rows commit atomically).
   * Returns the created item id when supplied with a target client, so the
   * review queue can record `applied_item_id`.
   */
  private static async createItemFromReceipt(
    userId: string,
    receipt: ExtractedReceipt,
    scanId: string,
  ): Promise<boolean>;
  private static async createItemFromReceipt(
    userId: string,
    receipt: ExtractedReceipt,
    scanId: string,
    targetClient: { query: (...args: any[]) => Promise<any> },
  ): Promise<string | null>;
  private static async createItemFromReceipt(
    userId: string,
    receipt: ExtractedReceipt,
    scanId: string,
    targetClient?: { query: (...args: any[]) => Promise<any> },
  ): Promise<boolean | string | null> {
    if (targetClient) {
      // Caller (approveReview) owns the transaction — the FOR UPDATE on
      // users + the items INSERT both run on its client.
      const itemId = await this.createItemUsing(targetClient, userId, receipt, scanId, false);
      return itemId;
    }

    // S2-M: keep the FOR UPDATE on users (line ~1388) and the items INSERT
    // in a single transaction so a concurrent scan worker can't slip in
    // between the plan check and the row creation. Rolls back on any
    // failure so a partial write never leaks.
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const itemId = await this.createItemUsing(client, userId, receipt, scanId, true);
      if (itemId === null) {
        await client.query('ROLLBACK');
        return false;
      }
      await client.query('COMMIT');
      return true;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  private static async createItemUsing(
    db: { query: (...args: any[]) => Promise<any> },
    userId: string,
    receipt: ExtractedReceipt,
    scanId: string,
    enforceFreeLimit: boolean,
  ): Promise<string | null> {
    if (enforceFreeLimit) {
      const userResult = await db.query(
        'SELECT plan FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE',
        [userId],
      );
      if (userResult.rows[0]?.plan === 'free') {
        const countResult = await db.query(
          'SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE',
          [userId],
        );
        const limit = config.freeTier.itemLimit;
        if (parseInt(countResult.rows[0].count, 10) >= limit) {
          logger.info({ userId, scanId }, 'Skipping item import: free plan limit reached');
          return null;
        }
      }
    }

    const homeResult = await db.query(
      'SELECT id FROM homes WHERE user_id = $1 ORDER BY created_at ASC LIMIT 1',
      [userId],
    );

    if (homeResult.rows.length === 0) {
      throw new AppError('User has no home', 400);
    }

    const homeId = homeResult.rows[0].id;

    const purchaseDate = receipt.purchaseDate
      ? new Date(receipt.purchaseDate)
      : new Date(receipt.emailDate || Date.now());

    // F066: prefer category_defaults.warranty_months over the hardcoded
    // 12. The model-extracted value wins when present (it parsed the email
    // body); the category default is a sensible fallback so a TV import
    // doesn't get a 12-month warranty when the store implies 24.
    const category = receipt.category || 'other';
    const defaultsRow = await db.query(
      'SELECT warranty_months FROM category_defaults WHERE category = $1',
      [category],
    );
    const fallbackMonths = (defaultsRow.rows[0]?.warranty_months as number | undefined) ?? 12;
    const warrantyMonths = receipt.warrantyPeriod || fallbackMonths;

    const warrantyEndDate = addMonthsSafe(purchaseDate, warrantyMonths);

    const insert = await db.query(
      `INSERT INTO items (
        home_id, user_id, name, brand, model_number, serial_number,
        category, purchase_date, store, price,
        warranty_months, warranty_end_date, warranty_type,
        notes, added_via
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
      RETURNING id`,
      [
        homeId,
        userId,
        receipt.productName,
        receipt.brand,
        receipt.modelNumber,
        receipt.serialNumber,
        receipt.category || 'other',
        purchaseDate,
        receipt.store,
        receipt.price,
        warrantyMonths,
        warrantyEndDate,
        'manufacturer',
        `Imported from email: ${receipt.emailSubject}`,
        'email',
      ],
    );

    const itemId = insert.rows[0]?.id as string;
    logger.info({ userId, scanId, productName: receipt.productName, itemId }, 'Item created from receipt');
    return itemId;
  }

  /**
   * Cancel an in-flight scan. Marks the row as `failed` with an explicit
   * "cancelled" message so the mobile UI's progress dialog can detach
   * cleanly. The background `performScan` task itself can keep running
   * (the AbortController lives in-process) — but UI-visible state flips
   * immediately and the final completed update guard
   * (`status != 'completed'`) keeps the cancellation sticky.
   */
  static async cancelScan(scanId: string, userId: string): Promise<EmailScan> {
    const result = await pool.query<EmailScan>(
      `UPDATE email_scans
          SET status = 'failed',
              error_message = 'Cancelled by user',
              completed_at = NOW()
        WHERE id = $1
          AND user_id = $2
          AND status IN ('pending', 'scanning')
        RETURNING *`,
      [scanId, userId],
    );

    if (result.rows.length === 0) {
      // Either no such scan or already terminal — surface the existing row
      // so the caller can decide whether to treat it as success.
      const existing = await pool.query<EmailScan>(
        'SELECT * FROM email_scans WHERE id = $1 AND user_id = $2',
        [scanId, userId],
      );
      if (existing.rows.length === 0) {
        throw new AppError('Scan not found', 404);
      }
      return existing.rows[0];
    }

    return result.rows[0];
  }

  /**
   * List a user's active OAuth integrations. Used by the mobile settings
   * screen to render granted-scope chips and the in-app disconnect button.
   * Refresh token ciphertext is intentionally omitted from the projection
   * — callers only need provider, email, scope, and timestamps.
   */
  static async listIntegrations(userId: string): Promise<
    Array<{
      id: string;
      provider: EmailScannerProvider;
      provider_email: string;
      granted_scope: string;
      created_at: Date;
      updated_at: Date;
      access_token_expires_at: Date | null;
    }>
  > {
    const result = await pool.query(
      `SELECT id, provider, provider_email, granted_scope,
              created_at, updated_at, access_token_expires_at
         FROM user_oauth_integrations
        WHERE user_id = $1 AND revoked_at IS NULL
        ORDER BY updated_at DESC`,
      [userId],
    );
    return result.rows;
  }

  /**
   * Get scan status
   */
  static async getScanStatus(scanId: string, userId: string): Promise<EmailScan> {
    try {
      const result = await pool.query(
        'SELECT * FROM email_scans WHERE id = $1 AND user_id = $2',
        [scanId, userId]
      );

      if (result.rows.length === 0) {
        throw new AppError('Scan not found', 404);
      }

      return result.rows[0];
    } catch (error) {
      logger.error({ error, scanId, userId }, 'Error fetching scan status');
      throw error;
    }
  }

  /**
   * Get user's scan history
   */
  static async getUserScans(userId: string): Promise<EmailScan[]> {
    try {
      const result = await pool.query(
        `SELECT * FROM email_scans
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 10`,
        [userId]
      );

      return result.rows;
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching user scans');
      throw error;
    }
  }

  /**
   * List a user's pending review queue rows.
   */
  static async listPendingReviews(userId: string): Promise<ReviewQueueRow[]> {
    const result = await pool.query<ReviewQueueRow>(
      `SELECT * FROM email_scanner_review_queue
        WHERE user_id = $1 AND state = 'pending'
        ORDER BY created_at DESC
        LIMIT 200`,
      [userId],
    );
    return result.rows;
  }

  /**
   * Approve a queued review row: create the item and mark the row applied.
   */
  static async approveReview(userId: string, reviewId: string): Promise<{ item_id: string }> {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const lock = await client.query<ReviewQueueRow>(
        `SELECT * FROM email_scanner_review_queue
          WHERE id = $1 AND user_id = $2
          FOR UPDATE`,
        [reviewId, userId],
      );

      if (lock.rows.length === 0) {
        throw new AppError('Review not found', 404);
      }

      const row = lock.rows[0];
      if (row.state !== 'pending') {
        throw new AppError(`Review already ${row.state}`, 409);
      }

      const itemId = await this.createItemFromReceipt(
        userId,
        row.suggested_item as ExtractedReceipt,
        row.email_scan_id,
        client,
      );

      if (!itemId) {
        throw new AppError('Unable to create item from review', 500);
      }

      await client.query(
        `UPDATE email_scanner_review_queue
            SET state = 'approved',
                applied_item_id = $2,
                reviewed_at = NOW()
          WHERE id = $1`,
        [reviewId, itemId],
      );

      await client.query('COMMIT');
      return { item_id: itemId };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Reject a queued review row.
   */
  static async rejectReview(
    userId: string,
    reviewId: string,
    reason?: string,
  ): Promise<void> {
    const result = await pool.query(
      `UPDATE email_scanner_review_queue
          SET state = 'rejected',
              rejection_reason = $3,
              reviewed_at = NOW()
        WHERE id = $1 AND user_id = $2 AND state = 'pending'`,
      [reviewId, userId, reason || null],
    );

    if (result.rowCount === 0) {
      // Either not found or already reviewed.
      const existing = await pool.query(
        'SELECT state FROM email_scanner_review_queue WHERE id = $1 AND user_id = $2',
        [reviewId, userId],
      );
      if (existing.rows.length === 0) {
        throw new AppError('Review not found', 404);
      }
      throw new AppError(`Review already ${existing.rows[0].state}`, 409);
    }
  }
}
