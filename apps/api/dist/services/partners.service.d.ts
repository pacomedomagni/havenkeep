import { Partner, PartnerGift, PartnerCommission } from '../types/database.types';
export declare class PartnersService {
    /**
     * Get or create a referral code for a partner user
     */
    static getOrCreateReferralCode(userId: string): Promise<string>;
    /**
     * Register as a partner (realtor/builder)
     */
    static registerPartner(userId: string, data: {
        partner_type: 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
        company_name?: string;
        phone?: string;
        website?: string;
        brand_color?: string;
        logo_url?: string;
        default_message?: string;
        service_areas?: string[];
    }): Promise<Partner>;
    /**
     * Get partner profile
     */
    static getPartner(userId: string): Promise<Partner>;
    /**
     * Update partner profile
     */
    static updatePartner(userId: string, data: {
        partner_type?: 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
        company_name?: string;
        phone?: string;
        website?: string;
        brand_color?: string;
        logo_url?: string;
        default_message?: string;
        default_premium_months?: number;
        service_areas?: string[];
    }): Promise<Partner>;
    /**
     * Create closing gift for homebuyer
     */
    static createGift(userId: string, data: {
        homebuyer_email: string;
        homebuyer_name: string;
        homebuyer_phone?: string;
        home_address?: string;
        closing_date?: string;
        premium_months?: number;
        custom_message?: string;
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
     */
    static activateGift(giftId: string, newUserId: string, userEmail: string): Promise<PartnerGift>;
    /**
     * Get partner analytics
     */
    static getPartnerAnalytics(userId: string): Promise<{
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