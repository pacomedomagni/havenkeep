import { Partner, PartnerGift, PartnerCommission } from '../types/database.types';
export declare class PartnersService {
    /**
     * Get or create a referral code for a partner user
     */
    static getOrCreateReferralCode(userId: string): Promise<string>;
    /**
     * Get users who signed up using this partner's referral code.
     * Returns paginated list with signup date, name, email (masked), and item count.
     */
    static getReferrals(userId: string, options: {
        page: number;
        limit: number;
    }): Promise<{
        referrals: Array<{
            id: string;
            full_name: string | null;
            email_masked: string;
            plan: string;
            item_count: number;
            signed_up_at: string;
        }>;
        total: number;
    }>;
    /**
     * Register as a partner (realtor/builder)
     */
    static registerPartner(userId: string, data: {
        partnerType: 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
        companyName?: string;
        phone?: string;
        website?: string;
        brandColor?: string;
        logoUrl?: string;
        defaultMessage?: string;
        serviceAreas?: string[];
        licenseNumber?: string | null;
    }): Promise<Partner>;
    /**
     * Get partner profile
     */
    static getPartner(userId: string): Promise<Partner>;
    /**
     * Update partner profile
     */
    static updatePartner(userId: string, data: {
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
    }): Promise<Partner>;
    /**
     * Create closing gift for homebuyer
     *
     * CRIT-2: Stripe charge is inside the transaction. The gift record is created
     * with 'pending_payment' status first, then Stripe is charged with an
     * idempotency key derived from the gift ID. If Stripe fails, the entire
     * transaction rolls back. If Stripe succeeds, the status is updated to
     * 'created' within the same transaction.
     */
    static createGift(userId: string, data: {
        homebuyerEmail: string;
        homebuyerName: string;
        homebuyerPhone?: string;
        homeAddress?: string;
        closingDate?: string;
        premiumMonths?: number;
        customMessage?: string;
    }): Promise<PartnerGift>;
    /**
     * Get partner's gifts
     */
    static getPartnerGifts(userId: string, options?: {
        limit?: number;
        offset?: number;
        status?: string;
    }): Promise<{
        gifts: PartnerGift[];
        total: number;
    }>;
    /**
     * Get gift by ID (for partner)
     */
    static getGift(giftId: string, userId: string): Promise<PartnerGift>;
    /**
     * Get public gift details (for preview before activation)
     */
    static getPublicGiftDetails(giftId: string): Promise<any>;
    /**
     * Verify activation code and return gift ID
     */
    static verifyActivationCode(code: string): Promise<{
        gift_id: string;
    }>;
    /**
     * Activate gift (when homebuyer signs up)
     *
     * BE-20: Uses SELECT ... FOR UPDATE to prevent concurrent activations.
     * BE-26: Verifies user email matches homebuyer_email on the gift.
     * HIGH-7: Per-gift rate limiting to prevent brute-force activation attempts.
     */
    static activateGift(giftId: string, newUserId: string, userEmail: string): Promise<PartnerGift>;
    /**
     * HIGH-7: Record a failed activation attempt for a gift.
     * After GIFT_MAX_ACTIVATION_ATTEMPTS failures, the gift is locked for
     * GIFT_LOCKOUT_DURATION_MS milliseconds.
     */
    private static recordFailedActivationAttempt;
    /**
     * Get partner analytics, optionally filtered by date range
     */
    static getPartnerAnalytics(userId: string, options?: {
        startDate?: string;
        endDate?: string;
    }): Promise<{
        total_gifts: number;
        activated_gifts: number;
        pending_gifts: number;
        activation_rate: number;
        total_commissions: number;
        pending_commissions: number;
        paid_commissions: number;
        recent_activity: any[];
    }>;
    /**
     * Get monthly earnings history for the last 12 months
     */
    static getEarningsHistory(partnerId: string): Promise<{
        month: string;
        earnings: number;
    }[]>;
    /**
     * Get partner commissions
     */
    static getCommissions(userId: string, options?: {
        limit?: number;
        offset?: number;
    }): Promise<{
        commissions: PartnerCommission[];
        total: number;
    }>;
    /**
     * Resend gift email to homebuyer
     */
    static resendGiftEmail(giftId: string, userId: string): Promise<void>;
}
//# sourceMappingURL=partners.service.d.ts.map