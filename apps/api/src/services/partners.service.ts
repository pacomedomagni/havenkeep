import { pool } from '../db';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';
import { Partner, PartnerGift, PartnerCommission } from '../types/database.types';
import Stripe from 'stripe';
import { config } from '../config';
import { EmailService } from './email.service';

const stripe = new Stripe(config.stripe.secretKey, {
  apiVersion: '2023-10-16',
});

export class PartnersService {
  /**
   * Register as a partner (realtor/builder)
   */
  static async registerPartner(
    userId: string,
    data: {
      partner_type: 'realtor' | 'builder' | 'contractor' | 'other';
      company_name?: string;
      phone?: string;
      website?: string;
      brand_color?: string;
      logo_url?: string;
      default_message?: string;
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
          brand_color, logo_url, default_message, subscription_tier
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'basic')
        RETURNING *`,
        [
          userId,
          data.partner_type,
          data.company_name,
          data.phone,
          data.website,
          data.brand_color || '#3B82F6',
          data.logo_url,
          data.default_message ||
            'Welcome to your new home! I\'m excited to share this tool to help you protect your appliances and warranties.',
        ]
      );

      const partner = result.rows[0];

      await client.query('COMMIT');

      // Send welcome email to new partner
      try {
        // Get user email
        const userResult = await client.query(
          'SELECT email, full_name FROM users WHERE id = $1',
          [userId]
        );

        if (userResult.rows.length > 0) {
          const user = userResult.rows[0];
          await EmailService.sendPartnerWelcomeEmail({
            to: user.email,
            partner_name: user.full_name || 'Partner',
            company_name: data.company_name,
          });
        }
      } catch (emailError) {
        // Log email error but don't fail partner registration
        logger.error(
          { error: emailError, partnerId: partner.id },
          'Failed to send partner welcome email, but registration was successful'
        );
      }

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
      company_name?: string;
      phone?: string;
      website?: string;
      brand_color?: string;
      logo_url?: string;
      default_message?: string;
      default_premium_months?: number;
    }
  ): Promise<Partner> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      const updates: string[] = [];
      const values: any[] = [];
      let paramIndex = 1;

      if (data.company_name !== undefined) {
        updates.push(`company_name = $${paramIndex++}`);
        values.push(data.company_name);
      }
      if (data.phone !== undefined) {
        updates.push(`phone = $${paramIndex++}`);
        values.push(data.phone);
      }
      if (data.website !== undefined) {
        updates.push(`website = $${paramIndex++}`);
        values.push(data.website);
      }
      if (data.brand_color !== undefined) {
        updates.push(`brand_color = $${paramIndex++}`);
        values.push(data.brand_color);
      }
      if (data.logo_url !== undefined) {
        updates.push(`logo_url = $${paramIndex++}`);
        values.push(data.logo_url);
      }
      if (data.default_message !== undefined) {
        updates.push(`default_message = $${paramIndex++}`);
        values.push(data.default_message);
      }
      if (data.default_premium_months !== undefined) {
        updates.push(`default_premium_months = $${paramIndex++}`);
        values.push(data.default_premium_months);
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
   */
  static async createGift(
    userId: string,
    data: {
      homebuyer_email: string;
      homebuyer_name: string;
      homebuyer_phone?: string;
      home_address?: string;
      closing_date?: string;
      premium_months?: number;
      custom_message?: string;
    }
  ): Promise<PartnerGift> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Get partner
      const partnerResult = await client.query(
        'SELECT * FROM partners WHERE user_id = $1',
        [userId]
      );

      if (partnerResult.rows.length === 0) {
        throw new AppError('Partner not found', 404);
      }

      const partner = partnerResult.rows[0];

      // Determine pricing based on tier
      const tierPricing = {
        basic: 99,
        premium: 149,
        platinum: 249,
      };

      const amountCharged = tierPricing[partner.subscription_tier as keyof typeof tierPricing];
      const premiumMonths = data.premium_months || partner.default_premium_months || 6;

      // Charge partner via Stripe
      const user = await client.query('SELECT stripe_customer_id FROM users WHERE id = $1', [
        userId,
      ]);

      let stripeChargeId = null;

      if (user.rows[0]?.stripe_customer_id) {
        try {
          const charge = await stripe.charges.create({
            amount: amountCharged * 100, // Convert to cents
            currency: 'usd',
            customer: user.rows[0].stripe_customer_id,
            description: `Closing gift for ${data.homebuyer_name}`,
            metadata: {
              partner_id: partner.id,
              homebuyer_email: data.homebuyer_email,
            },
          });

          stripeChargeId = charge.id;
        } catch (stripeError) {
          throw new AppError('Payment failed. Please check your payment method.', 402);
        }
      }

      // Create gift
      const expiresAt = new Date();
      expiresAt.setMonth(expiresAt.getMonth() + 6); // Gift link expires in 6 months

      const giftResult = await client.query(
        `INSERT INTO partner_gifts (
          partner_id, homebuyer_email, homebuyer_name, homebuyer_phone,
          home_address, closing_date, premium_months, custom_message,
          amount_charged, stripe_charge_id, expires_at, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'created')
        RETURNING *`,
        [
          partner.id,
          data.homebuyer_email.toLowerCase(),
          data.homebuyer_name,
          data.homebuyer_phone,
          data.home_address,
          data.closing_date,
          premiumMonths,
          data.custom_message || partner.default_message,
          amountCharged,
          stripeChargeId,
          expiresAt,
        ]
      );

      const gift = giftResult.rows[0];

      // Create commission record
      await client.query(
        `INSERT INTO partner_commissions (
          partner_id, type, amount, status, reference_id, reference_type
        ) VALUES ($1, 'gift', $2, 'pending', $3, 'partner_gift')`,
        [partner.id, amountCharged, gift.id]
      );

      await client.query('COMMIT');

      // Send email to homebuyer with gift activation link
      try {
        await EmailService.sendGiftActivationEmail({
          to: gift.homebuyer_email,
          homebuyer_name: gift.homebuyer_name,
          partner_name: partner.company_name || `Partner ${partner.id.slice(0, 8)}`,
          partner_company: partner.company_name,
          premium_months: gift.premium_months,
          activation_url: gift.activation_url,
          activation_code: gift.activation_code,
          custom_message: gift.custom_message,
          brand_color: partner.brand_color,
          logo_url: partner.logo_url,
        });
      } catch (emailError) {
        // Log email error but don't fail the gift creation
        logger.error(
          { error: emailError, giftId: gift.id, homebuyer: data.homebuyer_email },
          'Failed to send gift activation email, but gift was created successfully'
        );
      }

      logger.info(
        { giftId: gift.id, partnerId: partner.id, homebuyer: data.homebuyer_email },
        'Gift created'
      );

      return gift;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, userId }, 'Error creating gift');
      throw error;
    } finally {
      client.release();
    }
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
   * Verify activation code and return gift ID
   */
  static async verifyActivationCode(code: string): Promise<{ gift_id: string }> {
    try {
      const result = await pool.query(
        `SELECT id FROM partner_gifts WHERE activation_code = $1`,
        [code.toUpperCase()]
      );

      if (result.rows.length === 0) {
        throw new AppError('Invalid activation code', 404);
      }

      return { gift_id: result.rows[0].id };
    } catch (error) {
      logger.error({ error, code }, 'Error verifying activation code');
      throw error;
    }
  }

  /**
   * Activate gift (when homebuyer signs up)
   */
  static async activateGift(giftId: string, newUserId: string, userEmail: string): Promise<PartnerGift> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Get gift
      const giftResult = await client.query(
        'SELECT * FROM partner_gifts WHERE id = $1',
        [giftId]
      );

      if (giftResult.rows.length === 0) {
        throw new AppError('Gift not found', 404);
      }

      const gift = giftResult.rows[0];

      // Verify the calling user is the intended homebuyer
      if (gift.homebuyer_email.toLowerCase() !== userEmail.toLowerCase()) {
        throw new AppError('This gift was not issued to your email address', 403);
      }

      if (gift.is_activated) {
        throw new AppError('Gift already activated', 400);
      }

      if (gift.expires_at && new Date() > new Date(gift.expires_at)) {
        throw new AppError('Gift has expired', 400);
      }

      // Update gift
      await client.query(
        `UPDATE partner_gifts
         SET is_activated = TRUE,
             activated_at = NOW(),
             activated_user_id = $2,
             status = 'activated'
         WHERE id = $1`,
        [giftId, newUserId]
      );

      // Upgrade user to premium
      const premiumExpiresAt = new Date();
      premiumExpiresAt.setMonth(premiumExpiresAt.getMonth() + gift.premium_months);

      await client.query(
        `UPDATE users
         SET plan = 'premium',
             plan_expires_at = $2
         WHERE id = $1`,
        [newUserId, premiumExpiresAt]
      );

      // Update user analytics
      await client.query(
        `INSERT INTO user_analytics (user_id, has_activated_gift)
         VALUES ($1, TRUE)
         ON CONFLICT (user_id)
         DO UPDATE SET has_activated_gift = TRUE`,
        [newUserId]
      );

      await client.query('COMMIT');

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

  /**
   * Get partner analytics
   */
  static async getPartnerAnalytics(userId: string): Promise<{
    total_gifts: number;
    activated_gifts: number;
    pending_gifts: number;
    activation_rate: number;
    total_commissions: number;
    pending_commissions: number;
    paid_commissions: number;
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

      // Get gift stats
      const giftStats = await pool.query(
        `SELECT
           COUNT(*) as total_gifts,
           COUNT(*) FILTER (WHERE is_activated = TRUE) as activated_gifts,
           COUNT(*) FILTER (WHERE is_activated = FALSE AND status != 'expired') as pending_gifts
         FROM partner_gifts
         WHERE partner_id = $1`,
        [partnerId]
      );

      const stats = giftStats.rows[0];
      const activationRate =
        parseInt(stats.total_gifts) > 0
          ? (parseInt(stats.activated_gifts) / parseInt(stats.total_gifts)) * 100
          : 0;

      // Get commission stats
      const commissionStats = await pool.query(
        `SELECT
           SUM(amount) FILTER (WHERE status = 'pending') as pending_commissions,
           SUM(amount) FILTER (WHERE status = 'paid') as paid_commissions,
           SUM(amount) as total_commissions
         FROM partner_commissions
         WHERE partner_id = $1`,
        [partnerId]
      );

      const commissions = commissionStats.rows[0];

      // Get recent activity
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

      return {
        total_gifts: parseInt(stats.total_gifts),
        activated_gifts: parseInt(stats.activated_gifts),
        pending_gifts: parseInt(stats.pending_gifts),
        activation_rate: Math.round(activationRate),
        total_commissions: parseFloat(commissions.total_commissions) || 0,
        pending_commissions: parseFloat(commissions.pending_commissions) || 0,
        paid_commissions: parseFloat(commissions.paid_commissions) || 0,
        recent_activity: recentActivity.rows,
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching partner analytics');
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
