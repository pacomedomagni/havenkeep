import crypto from 'crypto';
import { Router } from 'express';
import { authenticate, requirePremium } from '../middleware/auth';
import { EmailScannerService } from '../services/email-scanner.service';
import { asyncHandler } from '../utils/async-handler';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { uuidParamSchema } from '../validators';
import { sendSuccess, sendMessage } from '../utils/response';
import { AppError } from '../utils/errors';
import { isOAuthEncryptionConfigured } from '../utils/oauth-encryption';
import { getRedisClient } from '../utils/redis';
import { config } from '../config';
import {
  emailScannerScanRateLimiter,
  emailScannerWriteRateLimiter,
} from '../middleware/rateLimiter';

// H47: server-issued OAuth state token. Mint flow:
//   1. Client calls POST /state-token → server returns `{state, ttl_seconds}`.
//   2. Client kicks off provider OAuth flow with `state` in the URL.
//   3. Provider redirects back to client with `code` + same `state`.
//   4. Client POSTs `{code, redirect_uri, state, ...}` to /scan.
//   5. Server validates HMAC, looks up Redis row, deletes on use.
// HMAC is over `${userId}.${nonce}.${expiresAtMs}` keyed with the
// JWT_SECRET; Redis stores a sentinel keyed by `oauth_state:${nonce}`
// so re-use is impossible.
const STATE_TTL_SECONDS = 5 * 60;

function mintOauthState(userId: string): { state: string; ttlSeconds: number } {
  const nonce = crypto.randomBytes(24).toString('base64url');
  const expiresAt = Date.now() + STATE_TTL_SECONDS * 1000;
  const payload = `${userId}.${nonce}.${expiresAt}`;
  const mac = crypto
    .createHmac('sha256', config.jwt.secret)
    .update(payload)
    .digest('base64url');
  return { state: `${payload}.${mac}`, ttlSeconds: STATE_TTL_SECONDS };
}

async function consumeOauthState(state: string, userId: string): Promise<void> {
  const parts = state.split('.');
  if (parts.length !== 4) {
    throw new AppError('Invalid OAuth state', 400);
  }
  const [claimUser, nonce, expStr, mac] = parts;
  if (claimUser !== userId) {
    throw new AppError('OAuth state belongs to a different user', 401);
  }
  const expiresAt = Number(expStr);
  if (!Number.isFinite(expiresAt) || expiresAt < Date.now()) {
    throw new AppError('OAuth state expired', 401);
  }
  const payload = `${claimUser}.${nonce}.${expStr}`;
  const expectedMac = crypto
    .createHmac('sha256', config.jwt.secret)
    .update(payload)
    .digest('base64url');
  // Use timingSafeEqual when lengths match; mismatch is itself a fail.
  const expectedBuf = Buffer.from(expectedMac, 'base64url');
  const macBuf = Buffer.from(mac, 'base64url');
  if (
    expectedBuf.length !== macBuf.length ||
    !crypto.timingSafeEqual(expectedBuf, macBuf)
  ) {
    throw new AppError('OAuth state signature mismatch', 401);
  }
  // Redis single-use: SET NX + EX, then DEL. Absence of the row at
  // verify time means the state was already consumed.
  const redis = await getRedisClient();
  const key = `oauth_state:${nonce}`;
  const setResult = await redis.set(key, userId, {
    EX: STATE_TTL_SECONDS,
    NX: true,
  });
  if (setResult !== 'OK') {
    // Either someone else won the NX (replay) or we already deleted it.
    throw new AppError('OAuth state has already been used', 401);
  }
  // Consume immediately so the same state can't be replayed even within
  // the TTL window.
  await redis.del(key);
}

const router = Router();

// All routes require authentication and premium plan
router.use(authenticate);
router.use(requirePremium);

/**
 * Initiate-scan body. The mobile/web client must send the OAuth
 * authorization `code` and the `redirect_uri` it used to obtain that code.
 * The server completes the code exchange — clients NEVER send a raw access
 * token. Any incoming `accessToken` / `access_token` field is rejected.
 */
// Snake_case API. Legacy `access_token` / `accessToken` fields are
// explicitly forbidden so a client that hasn't been updated fails loudly
// instead of silently sending a raw OAuth token the server no longer
// accepts.
// S-ME-06: allowlist the OAuth redirect_uri the client can pass to the
// token exchange. Google + Microsoft both bind redirect_uri to the
// auth-code grant on their side, but pinning it here too means a stolen
// auth code from a hostile client can't redirect tokens to an unexpected
// HavenKeep deploy / dev tunnel even if it happens to match an old
// registration. Configurable via `OAUTH_REDIRECT_URI_PREFIXES`
// (comma-separated). Defaults to the canonical mobile + web callbacks.
const OAUTH_REDIRECT_URI_PREFIXES = (
  process.env.OAUTH_REDIRECT_URI_PREFIXES ||
  'havenkeep://oauth-callback,https://havenkeep.com/oauth-callback,https://staging.havenkeep.app/oauth-callback'
)
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

function redirectUriAllowed(value: string, helpers: Joi.CustomHelpers): any {
  // H39: exact match on (protocol + host + path) so a prefix
  // `https://staging.havenkeep.app/oauth-callback` doesn't match
  // `https://staging.havenkeep.app/oauth-callback.attacker.com/...`
  // via a naive startsWith. The query/fragment is free to vary —
  // OAuth callbacks routinely append ?code= etc.
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    return helpers.error('any.invalid', { reason: 'redirect_uri is not a valid URL' });
  }
  const canonical = `${parsed.protocol}//${parsed.host}${parsed.pathname}`;
  const allowed = OAUTH_REDIRECT_URI_PREFIXES.some((prefix) => {
    try {
      const allowedParsed = new URL(prefix);
      const allowedCanonical = `${allowedParsed.protocol}//${allowedParsed.host}${allowedParsed.pathname}`;
      return canonical === allowedCanonical;
    } catch {
      // Non-URL prefix (e.g. havenkeep:// scheme has no host segment for
      // some platforms). Fall back to exact-match on the prefix.
      return value === prefix;
    }
  });
  if (!allowed) {
    return helpers.error('any.invalid', { reason: 'redirect_uri not in allowlist' });
  }
  return value;
}

const initiateScanSchema = Joi.object({
  provider: Joi.string().valid('gmail', 'outlook').required(),
  code: Joi.string().min(1).max(4096).required(),
  redirect_uri: Joi.string()
    .uri({ scheme: ['http', 'https', 'havenkeep'] })
    .custom(redirectUriAllowed, 'redirect_uri allowlist')
    .required(),
  // H47: server-issued OAuth `state` token. The client requests one via
  // POST /email-scanner/state-token before kicking off the OAuth
  // redirect, then echoes it back here. The server stored an HMAC-
  // signed (userId, timestamp) row in Redis on mint; we verify both
  // the signature AND the Redis presence (single-use). Replays fail.
  // Without server-side state, a malicious client could skip the check
  // entirely.
  state: Joi.string().min(20).max(512).required(),
  date_range_start: Joi.date().iso().optional(),
  date_range_end: Joi.date().iso().optional(),
  access_token: Joi.any().forbidden(),
  accessToken: Joi.any().forbidden(),
})
  .rename('redirectUri', 'redirect_uri', { ignoreUndefined: true, override: false })
  .rename('dateRangeStart', 'date_range_start', { ignoreUndefined: true, override: false })
  .rename('dateRangeEnd', 'date_range_end', { ignoreUndefined: true, override: false });

const reviewActionSchema = Joi.object({
  reason: Joi.string().max(500).optional(),
});

const providerQuerySchema = Joi.object({
  provider: Joi.string().valid('gmail', 'outlook').optional(),
});

/**
 * @route   POST /api/v1/email-scanner/scan
 * @desc    Exchange an OAuth code for tokens and start a scan
 * @access  Private (premium)
 */
// S-C6: per-user 5/hour limiter. /scan exchanges an OAuth code at the
// upstream provider, then performs a server-side mailbox scan; one
// compromised premium account previously could drain HavenKeep's per-app
// Google/Microsoft token-endpoint quota and DOS the scanner globally.
// H47: client requests a state token before opening the OAuth flow.
router.post(
  '/state-token',
  emailScannerWriteRateLimiter,
  asyncHandler(async (req, res) => {
    const minted = mintOauthState(req.user!.id);
    sendSuccess(res, { state: minted.state, ttl_seconds: minted.ttlSeconds });
  }),
);

router.post(
  '/scan',
  emailScannerScanRateLimiter,
  validate(initiateScanSchema),
  asyncHandler(async (req, res) => {
    if (!isOAuthEncryptionConfigured()) {
      throw new AppError('OAuth integration not configured', 503);
    }

    const userId = req.user!.id;
    const { provider, code, redirect_uri, state, date_range_start, date_range_end } = req.body;

    // H47: verify the state token before doing anything else. A
    // malicious / rebuilt client that skipped the state-token mint
    // step will fail here with a 401.
    await consumeOauthState(state, userId);

    const scan = await EmailScannerService.initiateScan(userId, provider, code, redirect_uri, {
      dateRangeStart: date_range_start,
      dateRangeEnd: date_range_end,
    });

    sendSuccess(res, scan, { status: 202, message: 'Email scan initiated. This may take a few minutes.' });
  })
);

/**
 * @route   GET /api/v1/email-scanner/scans/:id
 * @desc    Get email scan status
 * @access  Private
 */
router.get(
  '/scans/:id',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const scan = await EmailScannerService.getScanStatus(req.params.id, userId);

    sendSuccess(res, scan);
  })
);

/**
 * @route   GET /api/v1/email-scanner/scans
 * @desc    Get user's email scan history
 * @access  Private
 */
router.get(
  '/scans',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const scans = await EmailScannerService.getUserScans(userId);

    sendSuccess(res, scans);
  })
);

/**
 * @route   GET /api/v1/email-scanner/review
 * @desc    List pending review-queue rows for the authenticated user
 * @access  Private
 */
router.get(
  '/review',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const rows = await EmailScannerService.listPendingReviews(userId);
    sendSuccess(res, rows);
  })
);

/**
 * @route   POST /api/v1/email-scanner/review/:id/approve
 * @desc    Approve a queued review row, creating the underlying item
 * @access  Private
 */
router.post(
  '/review/:id/approve',
  emailScannerWriteRateLimiter,
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const result = await EmailScannerService.approveReview(userId, req.params.id);
    sendSuccess(res, result, { status: 201, message: 'Review approved and item created' });
  })
);

/**
 * @route   POST /api/v1/email-scanner/review/:id/reject
 * @desc    Reject a queued review row
 * @access  Private
 */
router.post(
  '/review/:id/reject',
  emailScannerWriteRateLimiter,
  validate(uuidParamSchema, 'params'),
  validate(reviewActionSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await EmailScannerService.rejectReview(userId, req.params.id, req.body?.reason);
    sendMessage(res, 'Review rejected');
  })
);

/**
 * @route   POST /api/v1/email-scanner/scans/:id/cancel
 * @desc    Cancel an in-flight scan; flips status to failed with a clear
 *          "cancelled" message so the mobile progress dialog can detach.
 * @access  Private
 */
router.post(
  '/scans/:id/cancel',
  emailScannerWriteRateLimiter,
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const scan = await EmailScannerService.cancelScan(req.params.id, userId);
    sendSuccess(res, scan, { message: 'Scan cancelled' });
  })
);

/**
 * @route   GET /api/v1/email-scanner/integrations
 * @desc    List the user's active OAuth integrations (provider, email,
 *          granted scopes). Powers the settings disconnect + scopes UI.
 * @access  Private
 */
router.get(
  '/integrations',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const integrations = await EmailScannerService.listIntegrations(userId);
    sendSuccess(res, integrations);
  })
);

/**
 * @route   DELETE /api/v1/email-scanner/integrations
 * @desc    Revoke OAuth integrations. Optional `?provider=gmail|outlook`
 *          query param targets a single provider; otherwise revokes all.
 * @access  Private
 */
router.delete(
  '/integrations',
  emailScannerWriteRateLimiter,
  validate(providerQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const provider = (req.query.provider as 'gmail' | 'outlook' | undefined) || undefined;
    await EmailScannerService.revokeIntegration(userId, provider);
    sendMessage(res, 'Integration revoked');
  })
);

export default router;
