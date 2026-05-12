import crypto from 'crypto';
import { pool } from '../db';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';
import { Partner, PartnerGift } from '../types/database.types';
import { config } from '../config';
import { EmailService } from './email.service';
import { getRedisClient } from '../utils/redis';
import { addMonthsSafe } from '../utils/dates';
import { invalidateUserCache } from '../middleware/auth';

/**
 * Gift duration in months. Every closing gift grants the homebuyer this many
 * months of HavenKeep premium. Hard-coded — partners cannot pick a length.
 * Six months balances "long enough to be useful" with "short enough that
 * account-cycling is irrational" (HavenKeep premium is $24/yr; the data
 * re-entry cost dwarfs any savings).
 */
export const GIFT_PREMIUM_MONTHS = 6;

/**
 * Activation codes are 64 bits of entropy, formatted XXXX-XXXX-XXXX-XXXX
 * (16 hex chars + 3 dashes). Stored hashed (SHA-256) in
 * partner_gifts.activation_code_hash and verified by hashing the user input
 * before lookup. Plaintext is held in `activation_code` (and the matching
 * `activation_url`) only while the gift can still be redeemed: it's needed
 * for the initial email, for partner-initiated resends, and for the
 * homebuyer typing the code into the activation form. Both fields are
 * nulled on a terminal transition — `activateGift` (gift redeemed,
 * plaintext is now exfil risk with no functional value) and the daily
 * `expireUnactivatedPartnerGifts` sweep (no further sends are valid).
 * verifyActivationCode goes through the hash, so the lookup keeps working
 * after the wipe.
 */
function generateActivationCode(): { plaintext: string; hash: string } {
  const raw = crypto.randomBytes(8).toString('hex').toUpperCase(); // 16 hex
  const plaintext = `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}`;
  return { plaintext, hash: hashActivationCode(plaintext) };
}

export function hashActivationCode(code: string): string {
  // Normalise: uppercase, strip dashes/whitespace, then SHA-256 hex.
  const normalized = code.replace(/[\s-]/g, '').toUpperCase();
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

// Per-gift activation-attempt rate limit. Independent from the per-code
// limit in routes/partners.ts (which is keyed on activation_code) — this
// one is keyed on gift_id and is hit AFTER the code has resolved to a
// specific gift, to slow brute-force "I have a gift_id, what's the right
// email?" probes.
const GIFT_MAX_ACTIVATION_ATTEMPTS = 5;
const GIFT_LOCKOUT_DURATION_SEC = 15 * 60;
const GIFT_ATTEMPT_WINDOW_SEC = 60 * 60;
const giftAttemptsKey = (giftId: string) => `gift:activate:attempts:${giftId}`;
const giftLockKey = (giftId: string) => `gift:activate:lock:${giftId}`;

export class PartnersService {
  static async registerPartner(
    userId: string,
    data: {
      partnerType: 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
      companyName?: string;
      phone?: string;
      website?: string;
      brandColor?: string;
      logoUrl?: string;
      defaultMessage?: string;
      serviceAreas?: string[];
    },
  ): Promise<Partner> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      const existing = await client.query(
        'SELECT id FROM partners WHERE user_id = $1',
        [userId],
      );
      if (existing.rows.length > 0) {
        // 409 is the semantic match — duplicate resource creation, not a
        // bad-request shape problem. The dashboard's /recover-profile
        // server action branches on 409 to redirect a racing user to
        // /dashboard instead of stranding them with a generic error
        // (audit H1 second-pass).
        throw new AppError('User is already registered as a partner', 409);
      }

      const result = await client.query(
        `INSERT INTO partners (
          user_id, partner_type, company_name, phone, website,
          brand_color, logo_url, default_message, service_areas
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING *`,
        [
          userId,
          data.partnerType,
          data.companyName,
          data.phone,
          data.website,
          data.brandColor || '#3B82F6',
          data.logoUrl,
          data.defaultMessage ||
            "Welcome to your new home! I'm excited to share this tool to help you protect your appliances and warranties.",
          data.serviceAreas || [],
        ],
      );

      const partner = result.rows[0];
      await client.query('COMMIT');

      // Fire-and-forget welcome email AFTER commit. Email failure must never
      // block partner registration.
      pool
        .query('SELECT email, full_name FROM users WHERE id = $1', [userId])
        .then((userResult) => {
          if (userResult.rows.length > 0) {
            const user = userResult.rows[0];
            return EmailService.sendPartnerWelcomeEmail({
              to: user.email,
              partner_name: user.full_name || 'Partner',
              company_name: data.companyName,
            });
          }
        })
        .catch((emailError) => {
          logger.error(
            { error: emailError, partnerId: partner.id },
            'Failed to send partner welcome email, but registration was successful',
          );
        });

      logger.info({ partnerId: partner.id, userId }, 'Partner registered');
      return partner;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      logger.error({ error, userId }, 'Error registering partner');
      throw error;
    } finally {
      client.release();
    }
  }

  static async getPartner(userId: string): Promise<Partner> {
    try {
      const result = await pool.query(
        `SELECT p.*, u.email, u.full_name
         FROM partners p
         JOIN users u ON u.id = p.user_id
         WHERE p.user_id = $1`,
        [userId],
      );

      if (result.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }

      return result.rows[0];
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching partner');
      throw error;
    }
  }

  static async updatePartner(
    userId: string,
    data: {
      partnerType?: 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
      companyName?: string;
      phone?: string;
      website?: string;
      brandColor?: string;
      logoUrl?: string;
      defaultMessage?: string;
      serviceAreas?: string[];
    },
  ): Promise<Partner> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      const updates: string[] = [];
      const values: any[] = [];
      let paramIndex = 1;

      if (data.partnerType !== undefined) {
        updates.push(`partner_type = $${paramIndex++}`);
        values.push(data.partnerType);
      }
      if (data.companyName !== undefined) {
        updates.push(`company_name = $${paramIndex++}`);
        values.push(data.companyName);
      }
      if (data.phone !== undefined) {
        updates.push(`phone = $${paramIndex++}`);
        values.push(data.phone);
      }
      if (data.website !== undefined) {
        updates.push(`website = $${paramIndex++}`);
        values.push(data.website);
      }
      if (data.brandColor !== undefined) {
        updates.push(`brand_color = $${paramIndex++}`);
        values.push(data.brandColor);
      }
      if (data.logoUrl !== undefined) {
        updates.push(`logo_url = $${paramIndex++}`);
        values.push(data.logoUrl);
      }
      if (data.defaultMessage !== undefined) {
        updates.push(`default_message = $${paramIndex++}`);
        values.push(data.defaultMessage);
      }
      if (data.serviceAreas !== undefined) {
        updates.push(`service_areas = $${paramIndex++}`);
        values.push(data.serviceAreas);
      }

      if (updates.length === 0) {
        throw new AppError('No fields to update', 400);
      }

      values.push(userId);

      const result = await client.query(
        `UPDATE partners
         SET ${updates.join(', ')}, updated_at = NOW()
         WHERE user_id = $${paramIndex++}
         RETURNING *`,
        values,
      );

      if (result.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }

      await client.query('COMMIT');

      logger.info({ userId }, 'Partner profile updated');
      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      logger.error({ error, userId }, 'Error updating partner');
      throw error;
    } finally {
      client.release();
    }
  }

  static async createGift(
    userId: string,
    data: {
      homebuyerEmail: string;
      homebuyerName: string;
      homebuyerPhone?: string;
      homeAddress?: string;
      closingDate?: string;
      customMessage?: string;
    },
  ): Promise<PartnerGift> {
    // Pre-allocate a unique activation code OUTSIDE any transaction. C12
    // (audit): retrying inside an open transaction puts the connection in
    // 25P02 and the retry guard never matches. A non-transactional pre-check
    // makes collisions vanishingly rare; the unique index on the INSERT
    // below still catches the residual concurrent-pre-check race, which we
    // surface as 409 so the caller retries the whole request.
    const PRE_CHECK_ATTEMPTS = 5;
    let activationCode = '';
    let activationCodeHash = '';
    for (let attempt = 0; attempt < PRE_CHECK_ATTEMPTS; attempt++) {
      const generated = generateActivationCode();
      const collision = await pool.query(
        `SELECT 1 FROM partner_gifts WHERE activation_code_hash = $1 LIMIT 1`,
        [generated.hash],
      );
      if (collision.rows.length === 0) {
        activationCode = generated.plaintext;
        activationCodeHash = generated.hash;
        break;
      }
      logger.warn(
        { attempt, partnerUserId: userId },
        'Activation code pre-check collision; retrying',
      );
    }
    if (!activationCodeHash) {
      throw new AppError(
        'Could not allocate a unique activation code — please retry the request',
        409,
      );
    }
    const activationUrl = `${config.app.frontendUrl}/gifts/activate?code=${encodeURIComponent(activationCode)}`;
    const expiresAt = addMonthsSafe(new Date(), GIFT_PREMIUM_MONTHS);

    const client = await pool.connect();
    let finalGift: any;
    let partner: any;
    try {
      await client.query('BEGIN');

      const partnerResult = await client.query(
        'SELECT * FROM partners WHERE user_id = $1',
        [userId],
      );
      if (partnerResult.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }
      partner = partnerResult.rows[0];

      const partnerUser = await client.query(
        'SELECT email FROM users WHERE id = $1',
        [userId],
      );
      const partnerEmail: string | undefined = partnerUser.rows[0]?.email?.toLowerCase();
      const homebuyerEmailLower = data.homebuyerEmail.toLowerCase();

      if (partnerEmail === homebuyerEmailLower) {
        throw new AppError('Cannot send a gift to your own email address', 400);
      }
      // Block obvious self-gift: if the homebuyer email is already attached
      // to a user the partner referred, the gift is going back to their own
      // referral network.
      const referredCheck = await client.query(
        `SELECT 1
           FROM users
          WHERE LOWER(email) = $1
            AND referred_by = $2
          LIMIT 1`,
        [homebuyerEmailLower, userId],
      );
      if (referredCheck.rows.length > 0) {
        throw new AppError(
          'This recipient is already part of your referral network. Self-gifting is not allowed.',
          400,
        );
      }

      let giftResult: import('pg').QueryResult;
      try {
        giftResult = await client.query(
          `INSERT INTO partner_gifts (
            partner_id, homebuyer_email, homebuyer_name, homebuyer_phone,
            home_address, closing_date, premium_months, custom_message,
            expires_at, status,
            activation_code, activation_code_hash, activation_url
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'created', $10, $11, $12)
          RETURNING *`,
          [
            partner.id,
            data.homebuyerEmail.toLowerCase(),
            data.homebuyerName,
            data.homebuyerPhone,
            data.homeAddress,
            data.closingDate,
            GIFT_PREMIUM_MONTHS,
            data.customMessage || partner.default_message,
            expiresAt,
            activationCode,
            activationCodeHash,
            activationUrl,
          ],
        );
      } catch (insertErr: any) {
        if (
          insertErr?.code === '23505' &&
          insertErr?.constraint === 'idx_partner_gifts_activation_code_hash'
        ) {
          logger.warn(
            { partnerId: partner.id },
            'Activation code race after pre-check; surfacing 409',
          );
          throw new AppError(
            'Could not allocate a unique activation code — please retry the request',
            409,
          );
        }
        throw insertErr;
      }
      finalGift = giftResult.rows[0];
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }

    // Send email to homebuyer with gift activation link (fire-and-forget).
    // Delivery failure must not undo a successful gift creation; the partner
    // can resend from the dashboard.
    EmailService.sendGiftActivationEmail({
      to: finalGift.homebuyer_email,
      homebuyer_name: finalGift.homebuyer_name,
      partner_name: partner.company_name || `Partner ${partner.id.slice(0, 8)}`,
      partner_company: partner.company_name,
      premium_months: finalGift.premium_months,
      activation_url: finalGift.activation_url,
      activation_code: finalGift.activation_code,
      custom_message: finalGift.custom_message,
      brand_color: partner.brand_color,
      logo_url: partner.logo_url,
      gift_id: finalGift.id,
    }).catch((emailError) => {
      logger.error(
        { error: emailError, giftId: finalGift.id, homebuyer: data.homebuyerEmail },
        'Failed to send gift activation email, but gift was created successfully',
      );
    });

    logger.info(
      { giftId: finalGift.id, partnerId: partner.id, homebuyer: data.homebuyerEmail },
      'Gift created',
    );

    return finalGift;
  }

  static async getPartnerGifts(
    userId: string,
    options: { limit?: number; offset?: number; status?: string } = {},
  ): Promise<{ gifts: PartnerGift[]; total: number }> {
    const { limit = 50, offset = 0, status } = options;

    try {
      const partnerResult = await pool.query(
        'SELECT id FROM partners WHERE user_id = $1',
        [userId],
      );

      if (partnerResult.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }

      const partnerId = partnerResult.rows[0].id;

      let query = `
        SELECT g.*,
               u.full_name as activated_user_name,
               u.email as activated_user_email
        FROM partner_gifts g
        LEFT JOIN users u ON u.id = g.activated_user_id
        WHERE g.partner_id = $1
      `;
      const params: any[] = [partnerId];

      if (status) {
        query += ` AND g.status = $${params.length + 1}`;
        params.push(status);
      }

      query += ` ORDER BY g.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      const countQuery = status
        ? 'SELECT COUNT(*) FROM partner_gifts WHERE partner_id = $1 AND status = $2'
        : 'SELECT COUNT(*) FROM partner_gifts WHERE partner_id = $1';
      const countParams = status ? [partnerId, status] : [partnerId];
      const countResult = await pool.query(countQuery, countParams);

      return {
        gifts: result.rows,
        total: parseInt(countResult.rows[0].count, 10),
      };
    } catch (error) {
      logger.error({ error, userId, options }, 'Error fetching partner gifts');
      throw error;
    }
  }

  static async getGift(giftId: string, userId: string): Promise<PartnerGift> {
    try {
      const result = await pool.query(
        `SELECT g.*, p.user_id
         FROM partner_gifts g
         JOIN partners p ON p.id = g.partner_id
         WHERE g.id = $1 AND p.user_id = $2`,
        [giftId, userId],
      );

      if (result.rows.length === 0) {
        throw new AppError('Gift not found', 404);
      }

      return result.rows[0];
    } catch (error) {
      logger.error({ error, giftId, userId }, 'Error fetching gift');
      throw error;
    }
  }

  static async getPublicGiftDetails(giftId: string): Promise<any> {
    try {
      const result = await pool.query(
        `SELECT g.id, g.homebuyer_name, g.premium_months, g.custom_message,
                g.is_activated, g.expires_at,
                p.company_name as partner_name, p.brand_color, p.logo_url
         FROM partner_gifts g
         JOIN partners p ON p.id = g.partner_id
         WHERE g.id = $1`,
        [giftId],
      );

      if (result.rows.length === 0) {
        throw new AppError('Gift not found', 404);
      }

      const gift = result.rows[0];

      if (gift.is_activated) {
        throw new AppError('Gift has already been activated', 400);
      }

      if (gift.expires_at && new Date() > new Date(gift.expires_at)) {
        throw new AppError('Gift has expired', 400);
      }

      return gift;
    } catch (error) {
      logger.error({ error, giftId }, 'Error fetching public gift details');
      throw error;
    }
  }

  /**
   * Verify activation code + email and return gift ID.
   *
   * Requires the homebuyer email as a second factor (Ch09-FlowC-T-C3): without
   * it, the endpoint is a code-enumeration oracle since a valid code always
   * 200s and a bogus code 404s. Both arms now return the same opaque error;
   * a successful verify only returns the gift id when both code AND email
   * match. The lookup is by hash (Ch09-FlowC-T-C16) so the DB never holds the
   * code in plaintext past the activation email's send window.
   */
  static async verifyActivationCode(
    code: string,
    homebuyerEmail: string,
  ): Promise<{ gift_id: string }> {
    try {
      const hash = hashActivationCode(code);
      const result = await pool.query(
        `SELECT id, homebuyer_email
           FROM partner_gifts
          WHERE activation_code_hash = $1
            AND status IN ('created', 'sent')
            AND (expires_at IS NULL OR expires_at > NOW())`,
        [hash],
      );

      const giftRow = result.rows[0];
      // Use a generic error so an attacker cannot distinguish "code unknown"
      // from "code valid but wrong email" or "expired".
      if (
        !giftRow ||
        giftRow.homebuyer_email.toLowerCase() !== homebuyerEmail.trim().toLowerCase()
      ) {
        throw new AppError('Invalid activation code or email', 404);
      }

      return { gift_id: giftRow.id };
    } catch (error) {
      if (!(error instanceof AppError)) {
        logger.error({ error }, 'Error verifying activation code');
      }
      throw error;
    }
  }

  /**
   * Activate gift (when homebuyer signs up)
   *
   * - SELECT ... FOR UPDATE prevents concurrent activations.
   * - Verifies the redeeming user's email matches homebuyer_email on the gift.
   * - Per-gift Redis-backed rate limiting prevents brute-force email guessing.
   */
  static async activateGift(
    giftId: string,
    newUserId: string,
    userEmail: string,
  ): Promise<PartnerGift> {
    await this.assertGiftNotLocked(giftId);

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      const giftResult = await client.query(
        'SELECT * FROM partner_gifts WHERE id = $1 FOR UPDATE',
        [giftId],
      );

      if (giftResult.rows.length === 0) {
        throw new AppError('Gift not found', 404);
      }

      const gift = giftResult.rows[0];

      if (gift.homebuyer_email.toLowerCase() !== userEmail.toLowerCase()) {
        await this.recordFailedActivationAttempt(giftId);
        throw new AppError('This gift was not issued to your email address', 403);
      }

      // Require email_verified before redeeming. Otherwise a partner could
      // self-gift to an unverified email they sign up to, then activate, and
      // earn premium on themselves (audit Ch09-FlowC-T-C5).
      const userRow = await client.query(
        `SELECT email_verified, plan FROM users WHERE id = $1 FOR UPDATE`,
        [newUserId],
      );
      if (userRow.rows.length === 0) {
        throw new AppError('User not found', 404);
      }
      if (!userRow.rows[0].email_verified) {
        throw new AppError(
          'Your email must be verified before activating a gift. Please confirm the address in your inbox first.',
          403,
        );
      }
      if (userRow.rows[0].plan === 'suspended') {
        // Suspended users cannot regain premium via gift activation; an admin
        // must unsuspend first (audit Ch03-F039).
        throw new AppError('Account is suspended; contact support before activating a gift', 403);
      }

      if (gift.status !== 'created' && gift.status !== 'sent') {
        if (gift.is_activated || gift.status === 'activated') {
          throw new AppError('Gift already activated', 400);
        }
        throw new AppError(`Gift cannot be activated (current status: ${gift.status})`, 400);
      }

      if (gift.expires_at && new Date() > new Date(gift.expires_at)) {
        throw new AppError('Gift has expired', 400);
      }

      // Race-safe activation (Ch03-F094). Two simultaneous sign-ups for the
      // same homebuyer email would otherwise both pass the FOR UPDATE check
      // and the second one's UPDATE would silently overwrite the first
      // activated_user_id. Guard the UPDATE with `activated_user_id IS NULL`
      // so only the first writer wins; the second sees 0 affected rows and
      // we surface a 409.
      //
      // Wipe plaintext activation_code + activation_url at the terminal
      // transition: the gift can no longer be redeemed via this row, so
      // holding the plaintext gives a DB-dump attacker a code that maps
      // to a known activated_user_id. The hash stays for audit/lookup.
      const updateResult = await client.query(
        `UPDATE partner_gifts
         SET is_activated = TRUE,
             activated_at = NOW(),
             activated_user_id = $2,
             status = 'activated',
             activation_code = NULL,
             activation_url = NULL
         WHERE id = $1
           AND activated_user_id IS NULL
           AND is_activated = FALSE`,
        [giftId, newUserId],
      );
      if (updateResult.rowCount === 0) {
        throw new AppError('Gift was activated by another account; redemption denied', 409);
      }

      // Stack premium months on top of any existing future expiry so multiple
      // gifts accumulate correctly instead of the later/shorter gift
      // overriding the longer one (or being silently swallowed).
      await client.query(
        `UPDATE users
            SET plan = 'premium',
                plan_expires_at =
                  CASE
                    WHEN plan_expires_at IS NULL OR plan_expires_at < NOW()
                      THEN NOW() + ($2::int || ' months')::interval
                    ELSE plan_expires_at + ($2::int || ' months')::interval
                  END,
                updated_at = NOW()
          WHERE id = $1`,
        [newUserId, gift.premium_months],
      );

      await client.query(
        `INSERT INTO user_analytics (user_id, has_activated_gift)
         VALUES ($1, TRUE)
         ON CONFLICT (user_id)
         DO UPDATE SET has_activated_gift = TRUE`,
        [newUserId],
      );

      await client.query('COMMIT');

      // 2.3: drop the user-row cache so any in-flight session sees the newly
      // granted premium plan without waiting for the 10s TTL.
      await invalidateUserCache(newUserId);

      await this.clearActivationAttempts(giftId);

      logger.info({ giftId, newUserId }, 'Gift activated');

      return (await pool.query('SELECT * FROM partner_gifts WHERE id = $1', [giftId])).rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      logger.error({ error, giftId, newUserId }, 'Error activating gift');
      throw error;
    } finally {
      client.release();
    }
  }

  private static async assertGiftNotLocked(giftId: string): Promise<void> {
    try {
      const redis = await getRedisClient();
      const lockTtl = await redis.ttl(giftLockKey(giftId));
      if (lockTtl > 0) {
        const remainingMin = Math.ceil(lockTtl / 60);
        throw new AppError(
          `This gift is temporarily locked due to too many failed attempts. Try again in ${remainingMin} minute(s).`,
          429,
        );
      }
    } catch (err) {
      if (err instanceof AppError) throw err;
      // Redis unavailable: allow request through (fail-open on rate limit;
      // the SELECT FOR UPDATE still prevents concurrent duplicate activation).
      logger.error({ err, giftId }, 'Gift lockout check failed, allowing through');
    }
  }

  private static async recordFailedActivationAttempt(giftId: string): Promise<void> {
    try {
      const redis = await getRedisClient();
      const attempts = await redis.incr(giftAttemptsKey(giftId));
      if (attempts === 1) {
        await redis.expire(giftAttemptsKey(giftId), GIFT_ATTEMPT_WINDOW_SEC);
      }
      if (attempts >= GIFT_MAX_ACTIVATION_ATTEMPTS) {
        await redis.set(giftLockKey(giftId), '1', { EX: GIFT_LOCKOUT_DURATION_SEC });
        logger.warn(
          { giftId, attempts, lockoutSec: GIFT_LOCKOUT_DURATION_SEC },
          'Gift locked due to too many failed activation attempts',
        );
      }
    } catch (err) {
      logger.error({ err, giftId }, 'Failed to record activation attempt in Redis');
    }
  }

  private static async clearActivationAttempts(giftId: string): Promise<void> {
    try {
      const redis = await getRedisClient();
      await redis.del([giftAttemptsKey(giftId), giftLockKey(giftId)]);
    } catch (err) {
      logger.error({ err, giftId }, 'Failed to clear gift activation attempts from Redis');
    }
  }

  /**
   * Gift activity summary for the partner dashboard. Pure counts — no money,
   * no commissions.
   */
  static async getPartnerAnalytics(userId: string): Promise<{
    total_gifts: number;
    activated_gifts: number;
    pending_gifts: number;
    activation_rate: number;
    recent_activity: Array<{
      name: string | null;
      status: string;
      created_at: string;
    }>;
  }> {
    try {
      const partnerResult = await pool.query(
        'SELECT id FROM partners WHERE user_id = $1',
        [userId],
      );
      if (partnerResult.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }
      const partnerId = partnerResult.rows[0].id;

      const [counts, recent] = await Promise.all([
        pool.query(
          `SELECT
             COUNT(*)::int AS total_gifts,
             COUNT(*) FILTER (WHERE is_activated)::int AS activated_gifts,
             COUNT(*) FILTER (WHERE status IN ('created', 'sent') AND NOT is_activated)::int AS pending_gifts
           FROM partner_gifts
          WHERE partner_id = $1`,
          [partnerId],
        ),
        pool.query(
          `SELECT homebuyer_name AS name, status, created_at
             FROM partner_gifts
            WHERE partner_id = $1
            ORDER BY created_at DESC
            LIMIT 10`,
          [partnerId],
        ),
      ]);

      const row = counts.rows[0];
      const total = row.total_gifts;
      const activated = row.activated_gifts;
      const activationRate = total === 0 ? 0 : Math.round((activated / total) * 100);

      return {
        total_gifts: total,
        activated_gifts: activated,
        pending_gifts: row.pending_gifts,
        activation_rate: activationRate,
        recent_activity: recent.rows,
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching partner analytics');
      throw error;
    }
  }

  /**
   * Resend gift email to homebuyer.
   */
  static async resendGiftEmail(giftId: string, userId: string): Promise<void> {
    try {
      const gift = await this.getGift(giftId, userId);

      if (gift.is_activated) {
        throw new AppError('Gift has already been activated', 400);
      }
      if (gift.expires_at && new Date() > new Date(gift.expires_at)) {
        throw new AppError('Gift has expired', 400);
      }
      // activation_code + activation_url are nulled on a terminal transition
      // (activate or expire). If we reach here without them, the daily expiry
      // sweep beat us between the time-window check above and this read —
      // refuse rather than send an empty email.
      if (!gift.activation_code || !gift.activation_url) {
        throw new AppError('Gift has expired', 400);
      }

      const partnerResult = await pool.query(
        'SELECT * FROM partners WHERE user_id = $1',
        [userId],
      );
      const partner = partnerResult.rows[0];

      await EmailService.sendGiftActivationEmail({
        to: gift.homebuyer_email,
        homebuyer_name: gift.homebuyer_name,
        partner_name: partner.company_name || `Partner ${partner.id.slice(0, 8)}`,
        partner_company: partner.company_name,
        premium_months: gift.premium_months,
        activation_url: gift.activation_url,
        activation_code: gift.activation_code,
        custom_message: gift.custom_message ?? undefined,
        brand_color: partner.brand_color ?? undefined,
        logo_url: partner.logo_url ?? undefined,
        gift_id: gift.id,
      });

      if (gift.status === 'created') {
        await pool.query(
          `UPDATE partner_gifts SET status = 'sent' WHERE id = $1`,
          [giftId],
        );
      }

      logger.info(
        { giftId, homebuyer: gift.homebuyer_email },
        'Gift email resent successfully',
      );
    } catch (error) {
      logger.error({ error, giftId, userId }, 'Error resending gift email');
      throw error;
    }
  }
}
