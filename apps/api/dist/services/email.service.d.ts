export declare class EmailService {
    /**
     * Send partner gift activation email to homebuyer
     */
    static sendGiftActivationEmail(data: {
        to: string;
        homebuyer_name: string;
        partner_name: string;
        partner_company?: string;
        premium_months: number;
        activation_url: string;
        activation_code: string;
        custom_message?: string;
        brand_color?: string;
        logo_url?: string;
        gift_id?: string;
    }): Promise<void>;
    /**
     * Send welcome email to new partner
     */
    static sendPartnerWelcomeEmail(data: {
        to: string;
        partner_name: string;
        company_name?: string;
    }): Promise<void>;
    /**
     * Send warranty expiration reminder email
     */
    static sendWarrantyExpirationEmail(data: {
        to: string;
        user_name: string;
        item_name: string;
        brand?: string;
        expiry_date: string;
        days_remaining: number;
        item_id: string;
    }): Promise<void>;
    /**
     * Send maintenance due reminder email
     */
    static sendMaintenanceDueEmail(data: {
        to: string;
        user_name: string;
        item_name: string;
        task_name: string;
        item_url: string;
    }): Promise<void>;
    /**
     * Send email verification email
     */
    static sendEmailVerificationEmail(data: {
        to: string;
        user_name: string;
        verify_url: string;
    }): Promise<void>;
    /**
     * Send email change verification email to the new address
     */
    static sendEmailChangeVerificationEmail(data: {
        to: string;
        user_name: string;
        verify_url: string;
        new_email: string;
    }): Promise<void>;
    /**
     * Send account deletion confirmation email
     */
    static sendAccountDeletionEmail(data: {
        to: string;
        user_name: string;
    }): Promise<void>;
    /**
     * Send password reset email
     */
    static sendPasswordResetEmail(data: {
        to: string;
        user_name: string;
        reset_url: string;
    }): Promise<void>;
    /**
     * Send contact form notification email to the support team
     */
    static sendContactNotificationEmail(data: {
        name: string;
        email: string;
        subject: string;
        message: string;
    }): Promise<void>;
}
//# sourceMappingURL=email.service.d.ts.map