import crypto from 'crypto';
import { pool, query } from '../db';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';
import { Partner, PartnerGift, PartnerCommission } from '../types/database.types';
import { config } from '../config';
import { createStripeClient } from '../utils/stripe-client';
import { EmailService } from './email.service';
import { generateUniqueReferralCode } from '../utils/referral-code';
import { getRedisClient } from '../utils/redis';
import { addMonthsSafe } from '../utils/dates';
import { commissionCents, dollarsToCents, centsToDecimalString, decimalToCents } from '../utils/money';
import { invalidateUserCache } from '../middleware/auth';

/**
 * Activation codes are 64 bits of entropy, formatted XXXX-XXXX-XXXX-XXXX
 * (16 hex chars + 3 dashes). Stored hashed (SHA-256) in
 * partner_gifts.activation_code_hash and verified by hashing the user input
 * before lookup. Plaintext is held in `activation_code` only long enough to
 * be embedded in the activation email and URL — Phase 5 follow-up nulls
 * `activation_code` once the email has shipped.
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

const stripe = createStripeClient();

// Tier pricing in dollars — configurable via env or DB in the future
const TIER_PRICING: Record<string, number> = JSON.parse(
  process.env.PARTNER_TIER_PRICING || '{"basic":99,"premium":149,"platinum":249}'
);

/**
 * Commission rates per tier (Ch03-F019, Ch12-T037). Locked here and in the
 * /partners/tiers route — diverging the two would let the dashboard
 * advertise a rate the API never pays. Tests guard the values explicitly.
 */
export const TIER_COMMISSION_RATES: Record<string, number> = {
  basic: 0.1,
  premium: 0.15,
  platinum: 0.2,
};


// MED-7: User-friendly messages for common Stripe decline codes
const STRIPE_DECLINE_MESSAGES: Record<string, string> = {
  card_declined: 'Your card was declined. Please try a different payment method.',
  insufficient_funds: 'Your card has insufficient funds. Please try a different payment method.',
  expired_card: 'Your card has expired. Please update your payment method.',
  incorrect_cvc: 'The CVC code is incorrect. Please check and try again.',
  processing_error: 'A processing error occurred. Please try again in a moment.',
  lost_card: 'This card has been reported lost. Please use a different payment method.',
  stolen_card: 'This card has been reported stolen. Please use a different payment method.',
  do_not_honor: 'Your bank declined this charge. Please contact your bank or try a different card.',
  generic_decline: 'Your card was declined. Please try a different payment method.',
};

// Gift activation brute-force protection. State lives in Redis so
// the lockout survives process restarts AND is shared across instances.
// Per-gift counter + lock TTL: after N failures, key is locked for the
// remainder of its TTL.
const GIFT_MAX_ACTIVATION_ATTEMPTS = 5;
const GIFT_LOCKOUT_DURATION_SEC = 15 * 60;
const GIFT_ATTEMPT_WINDOW_SEC = 60 * 60;

function giftAttemptsKey(giftId: string): string {
  return `gift:activate:attempts:${giftId}`;
}
function giftLockKey(giftId: string): string {
  return `gift:activate:lock:${giftId}`;
}

export class PartnersService {
  /**
   * Get or create a referral code for a partner user
   */
  static async getOrCreateReferralCode(userId: string): Promise<string> {
    // Ensure the user is a registered partner
    const partnerResult = await pool.query(
      'SELECT id FROM partners WHERE user_id = $1',
      [userId]
    );

    if (partnerResult.rows.length === 0) {
      throw new AppError('Partner not found', 404);
    }

    const userResult = await pool.query(
      'SELECT referral_code FROM users WHERE id = $1',
      [userId]
    );

    const existing = userResult.rows[0]?.referral_code;
    if (existing) {
      return existing;
    }

    const referralCode = await generateUniqueReferralCode();
    await pool.query(
      `UPDATE users SET referral_code = $1 WHERE id = $2`,
      [referralCode, userId]
    );

    return referralCode;
  }
  /**
   * Get users who signed up using this partner's referral code.
   * Returns paginated list with signup date, name, email (masked), and item count.
   */
  static async getReferrals(
    userId: string,
    options: { page: number; limit: number }
  ): Promise<{
    referrals: Array<{
      id: string;
      full_name: string | null;
      email_masked: string;
      plan: string;
      item_count: number;
      signed_up_at: string;
    }>;
    total: number;
  }> {
    // Verify partner exists
    const partnerResult = await pool.query(
      'SELECT id FROM partners WHERE user_id = $1',
      [userId]
    );
    if (partnerResult.rows.length === 0) {
      throw new AppError('Partner not found', 404);
    }

    const offset = (options.page - 1) * options.limit;

    const [rows, countResult] = await Promise.all([
      pool.query(
        `SELECT
           u.id,
           u.full_name,
           -- Mask email: show first 2 chars + domain for privacy
           CONCAT(
             LEFT(u.email, 2),
             '***@',
             SPLIT_PART(u.email, '@', 2)
           ) AS email_masked,
           u.plan,
           u.created_at AS signed_up_at,
           COALESCE(item_counts.cnt, 0)::integer AS item_count
         FROM users u
         LEFT JOIN (
           SELECT user_id, COUNT(*) AS cnt
           FROM items
           WHERE is_archived = FALSE
           GROUP BY user_id
         ) item_counts ON item_counts.user_id = u.id
         WHERE u.referred_by = $1
         ORDER BY u.created_at DESC
         LIMIT $2 OFFSET $3`,
        [userId, options.limit, offset]
      ),
      pool.query(
        `SELECT COUNT(*) FROM users WHERE referred_by = $1 AND deleted_at IS NULL`,
        [userId]
      ),
    ]);

    return {
      referrals: rows.rows,
      total: parseInt(countResult.rows[0].count, 10),
    };
  }

  /**
   * Register as a partner (realtor/builder)
   */
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
      licenseNumber?: string | null;
    }
  ): Promise<Partner> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Check if user is already a partner
      const existing = await client.query(
        'SELECT id FROM partners WHERE user_id = $1',
        [userId]
      );

      if (existing.rows.length > 0) {
        throw new AppError('User is already registered as a partner', 400);
      }

      // Create partner
      const result = await client.query(
        `INSERT INTO partners (
          user_id, partner_type, company_name, phone, website,
          brand_color, logo_url, default_message, service_areas, subscription_tier, license_number
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'basic', $10)
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
            'Welcome to your new home! I\'m excited to share this tool to help you protect your appliances and warranties.',
          data.serviceAreas || [],
          data.licenseNumber || null,
        ]
      );

      const partner = result.rows[0];

      await client.query('COMMIT');

      // MED-11: Fire-and-forget welcome email AFTER transaction commits.
      // Intentionally not awaited so email failure never blocks registration.
      pool.query('SELECT email, full_name FROM users WHERE id = $1', [userId])
        .then((userResult) => {
          if (userResult.rows.length > 0) {
            const user = userResult.rows[0];
            return EmailService.sendPartnerWelcomeEmail({
              to: user.email,
              partner_name: user.full_name || 'Partner',
              company_name: data.companyName,
              partner_id: partner.id,
            });
          }
        })
        .catch((emailError) => {
          logger.error(
            { error: emailError, partnerId: partner.id },
            'Failed to send partner welcome email, but registration was successful'
          );
        });

      logger.info({ partnerId: partner.id, userId }, 'Partner registered');

      return partner;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, userId }, 'Error registering partner');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get partner profile
   */
  static async getPartner(userId: string): Promise<Partner> {
    try {
      const result = await pool.query(
        `SELECT p.*, u.email, u.full_name
         FROM partners p
         JOIN users u ON u.id = p.user_id
         WHERE p.user_id = $1`,
        [userId]
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

  /**
   * Update partner profile
   */
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
      defaultPremiumMonths?: number;
      serviceAreas?: string[];
      licenseNumber?: string | null;
    }
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
      if (data.defaultPremiumMonths !== undefined) {
        updates.push(`default_premium_months = $${paramIndex++}`);
        values.push(data.defaultPremiumMonths);
      }
      if (data.serviceAreas !== undefined) {
        updates.push(`service_areas = $${paramIndex++}`);
        values.push(data.serviceAreas);
      }
      if (data.licenseNumber !== undefined) {
        updates.push(`license_number = $${paramIndex++}`);
        values.push(data.licenseNumber || null);
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
        values
      );

      if (result.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }

      await client.query('COMMIT');

      logger.info({ userId }, 'Partner profile updated');

      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, userId }, 'Error updating partner');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Create closing gift for homebuyer
   *
   * CRIT-2: Stripe charge is inside the transaction. The gift record is created
   * with 'pending_payment' status first, then Stripe is charged with an
   * idempotency key derived from the gift ID. If Stripe fails, the entire
   * transaction rolls back. If Stripe succeeds, the status is updated to
   * 'created' within the same transaction.
   */
  static async createGift(
    userId: string,
    data: {
      homebuyerEmail: string;
      homebuyerName: string;
      homebuyerPhone?: string;
      homeAddress?: string;
      closingDate?: string;
      premiumMonths?: number;
      customMessage?: string;
    }
  ): Promise<PartnerGift> {
    // --------------------------------------------------------------------
    // Phase 0: pre-allocate a unique activation code BEFORE the transaction
    // opens. C12 (audit): the prior implementation ran the retry loop
    // INSIDE the open transaction. After a single 23505 on the
    // activation_code_hash unique index, Postgres put the connection into
    // 25P02 (in_failed_sql_transaction); every subsequent INSERT raised
    // 25P02, NOT 23505, so the `if (insertErr.code === '23505')` retry
    // guard never matched. The "5 retries" defense was actually 0 retries.
    //
    // Now we collision-check non-transactionally — cheap PK-style index
    // lookup. The unique index inside the INSERT below still catches the
    // rare race where two concurrent createGift calls both pass the
    // pre-check with the same hash; one succeeds, the other gets a
    // single 23505 and we surface 409 to the caller (no inner retry
    // needed because the pre-check made collisions vanishingly rare).
    // --------------------------------------------------------------------
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

    // --------------------------------------------------------------------
    // Phase 1: reserve a gift row (pending_payment) in its own short tx.
    // Stripe calls MUST NOT run inside a DB transaction: a mid-tx Stripe
    // call that succeeds followed by a COMMIT failure leaves an orphan
    // charge. We keep DB work and Stripe work in separate atomic steps
    // and compensate with a refund if DB work fails after Stripe succeeds.
    // --------------------------------------------------------------------
    const reserveClient = await pool.connect();
    let gift: any;
    let partner: any;
    let amountCharged: number;
    try {
      await reserveClient.query('BEGIN');

      const partnerResult = await reserveClient.query(
        'SELECT * FROM partners WHERE user_id = $1',
        [userId],
      );
      if (partnerResult.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }
      partner = partnerResult.rows[0];

      const partnerUser = await reserveClient.query(
        'SELECT email, stripe_customer_id, referral_code FROM users WHERE id = $1',
        [userId],
      );
      const partnerEmail = partnerUser.rows[0]?.email?.toLowerCase();
      const homebuyerEmailLower = data.homebuyerEmail.toLowerCase();

      if (partnerEmail === homebuyerEmailLower) {
        throw new AppError('Cannot send a gift to your own email address', 400);
      }
      // Block obvious self-gift via referred users: if the homebuyer email is
      // already attached to a user that the partner referred, the gift is
      // funneling the partner's referral commission back to themselves.
      const referredCheck = await reserveClient.query(
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
      if (!partnerUser.rows[0]?.stripe_customer_id) {
        throw new AppError('Payment method required. Please add a payment method in your settings before creating gifts.', 402);
      }

      const tierAmount = TIER_PRICING[partner.subscription_tier];
      if (tierAmount === undefined) {
        throw new AppError(`Unknown subscription tier: ${partner.subscription_tier}`, 400);
      }
      amountCharged = tierAmount;

      const premiumMonths = data.premiumMonths || partner.default_premium_months || 6;
      // Gift activation window mirrors the premium grant length so a 12-month
      // gift can't be activated 6 months in (audit Ch03-F040).
      const expiresAt = addMonthsSafe(new Date(), premiumMonths);

      // C12: single INSERT with the pre-allocated code from Phase 0. The
      // unique index on activation_code_hash still catches the rare
      // concurrent-pre-check race; we map that 23505 to 409 so the caller
      // can retry the whole request, but no in-tx retry loop (which was
      // structurally broken under 25P02).
      let giftResult: import('pg').QueryResult;
      try {
        giftResult = await reserveClient.query(
          `INSERT INTO partner_gifts (
            partner_id, homebuyer_email, homebuyer_name, homebuyer_phone,
            home_address, closing_date, premium_months, custom_message,
            amount_charged, stripe_charge_id, expires_at, status,
            activation_code, activation_code_hash, activation_url
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NULL, $10, 'pending_payment', $11, $12, $13)
          RETURNING *`,
          [
            partner.id,
            data.homebuyerEmail.toLowerCase(),
            data.homebuyerName,
            data.homebuyerPhone,
            data.homeAddress,
            data.closingDate,
            premiumMonths,
            data.customMessage || partner.default_message,
            amountCharged,
            expiresAt,
            activationCode,
            activationCodeHash,
            activationUrl,
          ],
        );
      } catch (insertErr: any) {
        if (
          insertErr?.code === '23505' &&
          (insertErr?.constraint === 'idx_partner_gifts_activation_code_hash' ||
            insertErr?.constraint === 'uq_partner_gifts_activation_code')
        ) {
          // Concurrent createGift call landed on the same hash between
          // our pre-check and the INSERT. Vanishingly rare with 64-bit
          // codes and a non-locking pre-check; surface 409 so the caller
          // retries the whole request.
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
      gift = giftResult.rows[0];
      await reserveClient.query('COMMIT');
    } catch (error) {
      await reserveClient.query('ROLLBACK');
      throw error;
    } finally {
      reserveClient.release();
    }

    // --------------------------------------------------------------------
    // Phase 2: Stripe charge outside any DB transaction. Idempotency key
    // is `gift-<id>` so safe retries (including retries from an upstream
    // caller) never double-charge.
    // --------------------------------------------------------------------
    const partnerUserResult = await query(
      'SELECT stripe_customer_id FROM users WHERE id = $1',
      [userId],
    );
    const stripeCustomerId = partnerUserResult.rows[0]?.stripe_customer_id;

    let stripeChargeId: string;
    try {
      // Centralised dollar→cents conversion (Ch03-F020, F117).
      const amountCents = dollarsToCents(amountCharged);
      if (amountCents <= 0) {
        throw new AppError('Tier amount is invalid', 500);
      }
      const paymentIntent = await stripe.paymentIntents.create(
        {
          amount: amountCents,
          currency: 'usd',
          customer: stripeCustomerId,
          description: `Closing gift for ${data.homebuyerName}`,
          confirm: true,
          off_session: true,
          metadata: {
            partner_id: partner.id,
            gift_id: gift.id,
            homebuyer_email: data.homebuyerEmail,
          },
        },
        { idempotencyKey: `gift-${gift.id}` },
      );
      stripeChargeId = paymentIntent.id;
    } catch (stripeError: any) {
      const declineCode =
        stripeError?.code ||
        stripeError?.raw?.decline_code ||
        stripeError?.decline_code ||
        'generic_decline';
      logger.error(
        { error: stripeError?.message, declineCode, giftId: gift.id, userId },
        'Stripe payment failed for gift',
      );
      // Clean up the pending_payment gift row — no charge happened.
      try {
        await query(
          `UPDATE partner_gifts SET status = 'expired', updated_at = NOW() WHERE id = $1`,
          [gift.id],
        );
      } catch (cleanupErr) {
        logger.error({ err: cleanupErr, giftId: gift.id }, 'Failed to expire pending_payment gift after Stripe failure');
      }
      const userFriendlyMessage =
        STRIPE_DECLINE_MESSAGES[declineCode] ||
        'Payment failed. Please check your payment method and try again.';
      throw new AppError(userFriendlyMessage, 402);
    }

    // --------------------------------------------------------------------
    // Phase 3: promote gift to 'created' + create commission row. If this
    // fails, we have a live Stripe charge but no DB record, so issue a
    // refund (idempotent via `refund-<giftId>`) and surface the error.
    // --------------------------------------------------------------------
    const promoteClient = await pool.connect();
    try {
      await promoteClient.query('BEGIN');
      await promoteClient.query(
        `UPDATE partner_gifts
           SET status = 'created', stripe_charge_id = $1, updated_at = NOW()
         WHERE id = $2`,
        [stripeChargeId, gift.id],
      );
      // Tier-driven commission rate (Ch03-F019, Ch12-T037, Ch03-F116). Rates
      // are locked to 0.10 / 0.15 / 0.20 for basic / premium / platinum.
      // The DB has dropped the column DEFAULT (migration 041) so a missing
      // value would now violate NOT NULL — the rate must be passed explicitly.
      const commissionRate = TIER_COMMISSION_RATES[partner.subscription_tier];
      if (commissionRate === undefined) {
        throw new AppError(`Unknown subscription tier: ${partner.subscription_tier}`, 400);
      }
      const amountCentsForCommission = dollarsToCents(amountCharged);
      const commissionAmountStr = centsToDecimalString(
        commissionCents(amountCentsForCommission, commissionRate),
      );
      await promoteClient.query(
        `INSERT INTO partner_commissions (
          partner_id, type, amount, commission_rate, status, reference_id, reference_type
        ) VALUES ($1, 'gift', $2, $3, 'pending', $4, 'partner_gift')`,
        [partner.id, commissionAmountStr, commissionRate, gift.id],
      );
      await promoteClient.query('COMMIT');
    } catch (dbErr) {
      await promoteClient.query('ROLLBACK').catch(() => {});
      logger.error(
        { err: dbErr, giftId: gift.id, stripeChargeId },
        'DB finalization failed after Stripe charge — issuing refund',
      );
      try {
        await stripe.refunds.create(
          { payment_intent: stripeChargeId },
          { idempotencyKey: `refund-${gift.id}` },
        );
      } catch (refundErr) {
        logger.fatal(
          { err: refundErr, giftId: gift.id, stripeChargeId },
          'CRITICAL: Stripe refund failed after DB finalization failure — manual reconciliation required',
        );
      }
      throw dbErr;
    } finally {
      promoteClient.release();
    }

    const updatedGift = await pool.query('SELECT * FROM partner_gifts WHERE id = $1', [gift.id]);
    const finalGift = updatedGift.rows[0];

    // Send email to homebuyer with gift activation link (fire-and-forget).
    // Delivery failure is logged but must not undo a successful charge.
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

  /**
   * Get partner's gifts
   */
  static async getPartnerGifts(
    userId: string,
    options: {
      limit?: number;
      offset?: number;
      status?: string;
    } = {}
  ): Promise<{ gifts: PartnerGift[]; total: number }> {
    const { limit = 50, offset = 0, status } = options;

    try {
      // Get partner
      const partnerResult = await pool.query('SELECT id FROM partners WHERE user_id = $1', [
        userId,
      ]);

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

      query += ` ORDER BY g.created_at DESC`;
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      // Get total count
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

  /**
   * Get gift by ID (for partner)
   */
  static async getGift(giftId: string, userId: string): Promise<PartnerGift> {
    try {
      const result = await pool.query(
        `SELECT g.*, p.user_id
         FROM partner_gifts g
         JOIN partners p ON p.id = g.partner_id
         WHERE g.id = $1 AND p.user_id = $2`,
        [giftId, userId]
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

  /**
   * Get public gift details (for preview before activation)
   */
  static async getPublicGiftDetails(giftId: string): Promise<any> {
    try {
      const result = await pool.query(
        `SELECT g.id, g.homebuyer_name, g.premium_months, g.custom_message,
                g.is_activated, g.expires_at,
                p.company_name as partner_name, p.brand_color, p.logo_url
         FROM partner_gifts g
         JOIN partners p ON p.id = g.partner_id
         WHERE g.id = $1`,
        [giftId]
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
   * BE-20: Uses SELECT ... FOR UPDATE to prevent concurrent activations.
   * BE-26: Verifies user email matches homebuyer_email on the gift.
   * HIGH-7: Per-gift rate limiting to prevent brute-force activation attempts.
   */
  static async activateGift(giftId: string, newUserId: string, userEmail: string): Promise<PartnerGift> {
    // Lockout check via Redis — survives restarts, shared across nodes.
    await this.assertGiftNotLocked(giftId);

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // SELECT ... FOR UPDATE to prevent concurrent activations
      const giftResult = await client.query(
        'SELECT * FROM partner_gifts WHERE id = $1 FOR UPDATE',
        [giftId]
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
      // earn commission on themselves (audit Ch09-FlowC-T-C5).
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
        // Suspended users cannot regain access to premium via gift activation;
        // an admin must unsuspend first (audit Ch03-F039).
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
      const updateResult = await client.query(
        `UPDATE partner_gifts
         SET is_activated = TRUE,
             activated_at = NOW(),
             activated_user_id = $2,
             status = 'activated'
         WHERE id = $1
           AND activated_user_id IS NULL
           AND is_activated = FALSE`,
        [giftId, newUserId]
      );
      if (updateResult.rowCount === 0) {
        throw new AppError('Gift was activated by another account; redemption denied', 409);
      }

      // Stack premium months on top of any existing future expiry so
      // multiple gifts accumulate correctly instead of the later/shorter
      // gift overriding the longer one (or being silently swallowed).
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
        [newUserId]
      );

      await client.query('COMMIT');

      // 2.3: drop the user-row cache so any in-flight session sees the
      // newly granted premium plan without waiting for the 10s TTL.
      await invalidateUserCache(newUserId);

      // Clear rate-limit tracking on successful activation
      await this.clearActivationAttempts(giftId);

      logger.info({ giftId, newUserId }, 'Gift activated');

      return (
        await pool.query('SELECT * FROM partner_gifts WHERE id = $1', [giftId])
      ).rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
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
      // Redis unavailable: allow request through (fail-open on rate limit,
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
   * Get partner analytics, optionally filtered by date range
   */
  static async getPartnerAnalytics(
    userId: string,
    options?: { startDate?: string; endDate?: string }
  ): Promise<{
    total_gifts: number;
    activated_gifts: number;
    pending_gifts: number;
    activation_rate: number;
    // S3-A: cent-accurate decimal strings (e.g. "7.00"). Display layer
    // formats; doing math on these is a bug — prefer the raw cents.
    total_commissions: string;
    pending_commissions: string;
    paid_commissions: string;
    recent_activity: any[];
  }> {
    try {
      // Get partner
      const partnerResult = await pool.query('SELECT id FROM partners WHERE user_id = $1', [
        userId,
      ]);

      if (partnerResult.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }

      const partnerId = partnerResult.rows[0].id;

      // Build date range conditions
      const giftParams: any[] = [partnerId];
      let giftDateFilter = '';
      const commissionParams: any[] = [partnerId];
      let commissionDateFilter = '';

      if (options?.startDate) {
        giftParams.push(options.startDate);
        giftDateFilter += ` AND created_at >= $${giftParams.length}`;
        commissionParams.push(options.startDate);
        commissionDateFilter += ` AND created_at >= $${commissionParams.length}`;
      }
      if (options?.endDate) {
        giftParams.push(options.endDate);
        giftDateFilter += ` AND created_at <= $${giftParams.length}`;
        commissionParams.push(options.endDate);
        commissionDateFilter += ` AND created_at <= $${commissionParams.length}`;
      }

      // Get gift stats
      const giftStats = await pool.query(
        `SELECT
           COUNT(*) as total_gifts,
           COUNT(*) FILTER (WHERE is_activated = TRUE) as activated_gifts,
           COUNT(*) FILTER (WHERE is_activated = FALSE AND status != 'expired') as pending_gifts
         FROM partner_gifts
         WHERE partner_id = $1${giftDateFilter}`,
        giftParams
      );

      const stats = giftStats.rows[0];
      const activationRate =
        parseInt(stats.total_gifts) > 0
          ? (parseInt(stats.activated_gifts) / parseInt(stats.total_gifts)) * 100
          : 0;

      // Get commission stats. paid_commissions only counts rows where the
      // Stripe transfer id is non-null — a 'paid' DB flag without a transfer
      // is a stuck row, not money the partner has received (audit F054).
      // Reversal rows (negative amount, status='reversed') subtract from the
      // paid total automatically since SUM is signed.
      const commissionStats = await pool.query(
        `SELECT
           SUM(amount) FILTER (WHERE status = 'pending') as pending_commissions,
           SUM(amount) FILTER (WHERE status = 'paid' AND stripe_transfer_id IS NOT NULL) as paid_commissions,
           SUM(amount) as total_commissions
         FROM partner_commissions
         WHERE partner_id = $1${commissionDateFilter}`,
        commissionParams
      );

      const commissions = commissionStats.rows[0];

      // Get recent activity (always show latest, no date filter)
      const recentActivity = await pool.query(
        `SELECT
           'gift_created' as type,
           g.id,
           g.homebuyer_name as name,
           g.created_at,
           g.status
         FROM partner_gifts g
         WHERE g.partner_id = $1
         ORDER BY g.created_at DESC
         LIMIT 10`,
        [partnerId]
      );

      // S3-A: aggregate in integer cents and only convert to a display
      // string at the response edge. parseFloat on DECIMAL would compound
      // float drift at the 100-row scale (100 × $0.07 → $6.999999).
      return {
        total_gifts: parseInt(stats.total_gifts),
        activated_gifts: parseInt(stats.activated_gifts),
        pending_gifts: parseInt(stats.pending_gifts),
        activation_rate: Math.round(activationRate),
        total_commissions: centsToDecimalString(decimalToCents(commissions.total_commissions)),
        pending_commissions: centsToDecimalString(decimalToCents(commissions.pending_commissions)),
        paid_commissions: centsToDecimalString(decimalToCents(commissions.paid_commissions)),
        recent_activity: recentActivity.rows,
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching partner analytics');
      throw error;
    }
  }

  /**
   * Get monthly earnings history for the last 12 months
   */
  static async getEarningsHistory(partnerId: string): Promise<{ month: string; earnings: number }[]> {
    try {
      const result = await pool.query(
        `SELECT
           date_trunc('month', created_at) as month,
           SUM(amount) as earnings
         FROM partner_commissions
         WHERE partner_id = $1 AND status IN ('approved', 'paid') AND created_at >= NOW() - INTERVAL '12 months'
         GROUP BY date_trunc('month', created_at)
         ORDER BY month ASC`,
        [partnerId]
      );

      return result.rows.map((row: any) => ({
        month: new Date(row.month).toLocaleString('en-US', { month: 'short' }),
        earnings: parseFloat(row.earnings) || 0,
      }));
    } catch (error) {
      logger.error({ error, partnerId }, 'Error fetching earnings history');
      throw error;
    }
  }

  /**
   * Get partner commissions
   */
  static async getCommissions(
    userId: string,
    options: { limit?: number; offset?: number } = {}
  ): Promise<{ commissions: PartnerCommission[]; total: number }> {
    const { limit = 50, offset = 0 } = options;

    try {
      // Get partner
      const partnerResult = await pool.query('SELECT id FROM partners WHERE user_id = $1', [
        userId,
      ]);

      if (partnerResult.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }

      const partnerId = partnerResult.rows[0].id;

      const result = await pool.query(
        `SELECT c.*,
                CASE
                  WHEN c.reference_type = 'partner_gift' THEN g.homebuyer_name
                  ELSE NULL
                END as reference_name
         FROM partner_commissions c
         LEFT JOIN partner_gifts g ON g.id = c.reference_id AND c.reference_type = 'partner_gift'
         WHERE c.partner_id = $1
         ORDER BY c.created_at DESC
         LIMIT $2 OFFSET $3`,
        [partnerId, limit, offset]
      );

      const countResult = await pool.query(
        'SELECT COUNT(*) FROM partner_commissions WHERE partner_id = $1',
        [partnerId]
      );

      return {
        commissions: result.rows,
        total: parseInt(countResult.rows[0].count, 10),
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching commissions');
      throw error;
    }
  }

  /**
   * Resend gift email to homebuyer
   */
  static async resendGiftEmail(giftId: string, userId: string): Promise<void> {
    try {
      // Verify gift belongs to this partner
      const gift = await this.getGift(giftId, userId);

      if (gift.is_activated) {
        throw new AppError('Gift has already been activated', 400);
      }

      if (gift.expires_at && new Date() > new Date(gift.expires_at)) {
        throw new AppError('Gift has expired', 400);
      }

      // Get partner details for email
      const partnerResult = await pool.query(
        'SELECT * FROM partners WHERE user_id = $1',
        [userId]
      );

      const partner = partnerResult.rows[0];

      // Send email with activation link
      await EmailService.sendGiftActivationEmail({
        to: gift.homebuyer_email,
        homebuyer_name: gift.homebuyer_name,
        partner_name: partner.company_name || `Partner ${partner.id.slice(0, 8)}`,
        partner_company: partner.company_name,
        premium_months: gift.premium_months,
        activation_url: gift.activation_url ?? '',
        activation_code: gift.activation_code ?? '',
        custom_message: gift.custom_message ?? undefined,
        brand_color: partner.brand_color ?? undefined,
        logo_url: partner.logo_url ?? undefined,
        gift_id: gift.id,
      });

      // Update gift status to 'sent' if it was 'created'
      if (gift.status === 'created') {
        await pool.query(
          `UPDATE partner_gifts SET status = 'sent' WHERE id = $1`,
          [giftId]
        );
      }

      logger.info(
        {
          giftId,
          homebuyer: gift.homebuyer_email,
        },
        'Gift email resent successfully'
      );
    } catch (error) {
      logger.error({ error, giftId, userId }, 'Error resending gift email');
      throw error;
    }
  }
}
