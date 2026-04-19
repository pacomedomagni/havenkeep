export type ItemCategory = 'refrigerator' | 'dishwasher' | 'washer' | 'dryer' | 'oven_range' | 'microwave' | 'garbage_disposal' | 'range_hood' | 'hvac' | 'water_heater' | 'furnace' | 'water_softener' | 'sump_pump' | 'tv' | 'computer' | 'smart_home' | 'roofing' | 'windows' | 'doors' | 'flooring' | 'plumbing' | 'electrical' | 'furniture' | 'air_purifier' | 'vacuum' | 'ceiling_fan' | 'smoke_detector' | 'security_system' | 'garage_door_opener' | 'power_tools' | 'lawn_mower' | 'pool_equipment' | 'grill' | 'coffee_maker' | 'home_theater' | 'printer' | 'networking' | 'camera' | 'lighting' | 'dehumidifier' | 'freezer' | 'wine_cooler' | 'trash_compactor' | 'other';
export type EmailScanStatus = 'pending' | 'scanning' | 'completed' | 'failed';
export type PartnerType = 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
export type PartnerTier = 'basic' | 'premium' | 'platinum';
export type GiftStatus = 'pending_payment' | 'payment_failed' | 'created' | 'sent' | 'activated' | 'expired';
export type CommissionStatus = 'pending' | 'approved' | 'paid' | 'cancelled';
export type CommissionType = 'gift' | 'warranty_sale' | 'referral' | 'subscription';
export type WarrantyPurchaseStatus = 'pending' | 'active' | 'expired' | 'cancelled' | 'claimed';
export interface WarrantyClaim {
    id: string;
    item_id: string;
    user_id: string;
    claim_date: Date;
    issue_description: string | null;
    repair_description: string | null;
    repair_cost: number;
    amount_saved: number;
    out_of_pocket: number | null;
    status: string;
    filed_with: string | null;
    claim_number: string | null;
    notes: string | null;
    created_at: Date;
    updated_at: Date;
}
export interface MaintenanceSchedule {
    id: string;
    category: ItemCategory;
    task_name: string;
    description: string | null;
    frequency_months: number;
    frequency_label: string | null;
    estimated_duration_minutes: number | null;
    difficulty: 'easy' | 'medium' | 'hard';
    prevents_cost: number | null;
    how_to_url: string | null;
    video_url: string | null;
    tools_needed: string[] | null;
    is_required_for_warranty: boolean;
    priority: number;
    created_at: Date;
    updated_at: Date;
}
export interface MaintenanceHistory {
    id: string;
    item_id: string;
    user_id: string;
    schedule_id: string | null;
    task_name: string;
    completed_date: Date;
    notes: string | null;
    duration_minutes: number | null;
    cost: number;
    created_at: Date;
}
export interface EmailScan {
    id: string;
    user_id: string;
    provider: string;
    provider_email: string | null;
    scan_date: Date;
    date_range_start: Date | null;
    date_range_end: Date | null;
    emails_scanned: number;
    receipts_found: number;
    items_imported: number;
    status: EmailScanStatus;
    error_message: string | null;
    completed_at: Date | null;
    created_at: Date;
}
export interface Partner {
    id: string;
    user_id: string;
    partner_type: PartnerType;
    company_name: string | null;
    phone: string | null;
    website: string | null;
    brand_color: string | null;
    logo_url: string | null;
    subscription_tier: PartnerTier;
    default_message: string | null;
    default_premium_months: number;
    service_areas: string[];
    license_number: string | null;
    stripe_account_id: string | null;
    stripe_onboarded: boolean;
    is_active: boolean;
    is_verified: boolean;
    created_at: Date;
    updated_at: Date;
}
export interface PartnerGift {
    id: string;
    partner_id: string;
    homebuyer_email: string;
    homebuyer_name: string;
    homebuyer_phone: string | null;
    home_address: string | null;
    closing_date: Date | null;
    premium_months: number;
    custom_message: string | null;
    status: GiftStatus;
    is_activated: boolean;
    activation_code: string | null;
    activation_url: string | null;
    activated_at: Date | null;
    activated_user_id: string | null;
    expires_at: Date | null;
    amount_charged: number;
    stripe_charge_id: string | null;
    email_opened_at: Date | null;
    app_download_at: Date | null;
    first_item_added_at: Date | null;
    created_at: Date;
    updated_at: Date;
}
export interface PartnerCommission {
    id: string;
    partner_id: string;
    type: CommissionType;
    amount: number;
    description: string | null;
    status: CommissionStatus;
    approved_at: Date | null;
    paid_at: Date | null;
    reference_id: string | null;
    reference_type: string | null;
    stripe_transfer_id: string | null;
    payout_method: string;
    created_at: Date;
    updated_at: Date;
}
export interface WarrantyPurchase {
    id: string;
    item_id: string;
    user_id: string;
    provider: string;
    plan_name: string;
    external_policy_id: string | null;
    duration_months: number;
    starts_at: Date;
    expires_at: Date;
    coverage_details: Record<string, any> | null;
    price: number;
    deductible: number;
    claim_limit: number | null;
    commission_amount: number | null;
    commission_rate: number | null;
    purchase_date: Date;
    stripe_payment_intent_id: string | null;
    status: WarrantyPurchaseStatus;
    cancelled_at: Date | null;
    cancellation_reason: string | null;
    created_at: Date;
    updated_at: Date;
}
export interface UserAnalytics {
    id: string;
    user_id: string;
    last_active_at: Date | null;
    total_app_opens: number;
    total_sessions: number;
    avg_session_duration_seconds: number;
    current_health_score: number;
    health_score_history: Array<{
        date: string;
        score: number;
    }>;
    total_warranty_savings: number;
    total_preventive_savings: number;
    total_claims_filed: number;
    total_maintenance_completed: number;
    email_scans_completed: number;
    items_added_manually: number;
    items_added_via_email: number;
    items_added_via_barcode: number;
    documents_uploaded: number;
    reports_generated: number;
    has_activated_gift: boolean;
    has_completed_onboarding: boolean;
    has_added_first_item: boolean;
    has_scanned_email: boolean;
    has_filed_claim: boolean;
    updated_at: Date;
}
export interface SavingsFeedEntry {
    id: string;
    user_city: string | null;
    user_state: string | null;
    amount_saved: number;
    item_category: ItemCategory | null;
    claim_type: string | null;
    display_text: string | null;
    created_at: Date;
}
export interface DashboardStats {
    total_value: number;
    total_items: number;
    active_warranties: number;
    expiring_soon: number;
    expired: number;
    total_repair_value: number;
    health_score: number;
}
export interface CreateWarrantyClaimDto {
    itemId: string;
    claimDate?: string;
    issueDescription?: string;
    repairDescription?: string;
    repairCost: number;
    amountSaved: number;
    outOfPocket?: number;
    status?: string;
    filedWith?: string;
    claimNumber?: string;
    notes?: string;
}
export interface CreateMaintenanceHistoryDto {
    itemId: string;
    scheduleId?: string;
    taskName: string;
    completedDate?: string;
    notes?: string;
    durationMinutes?: number;
    cost?: number;
}
//# sourceMappingURL=database.types.d.ts.map