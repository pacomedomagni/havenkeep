// ============================================
// Database Types for HavenKeep
// Auto-generated from PostgreSQL schema
// ============================================

export type ItemCategory =
  | 'refrigerator'
  | 'dishwasher'
  | 'washer'
  | 'dryer'
  | 'oven_range'
  | 'microwave'
  | 'garbage_disposal'
  | 'range_hood'
  | 'hvac'
  | 'water_heater'
  | 'furnace'
  | 'water_softener'
  | 'sump_pump'
  | 'tv'
  | 'computer'
  | 'smart_home'
  | 'roofing'
  | 'windows'
  | 'doors'
  | 'flooring'
  | 'plumbing'
  | 'electrical'
  | 'furniture'
  | 'air_purifier'
  | 'vacuum'
  | 'ceiling_fan'
  | 'smoke_detector'
  | 'security_system'
  | 'garage_door_opener'
  | 'power_tools'
  | 'lawn_mower'
  | 'pool_equipment'
  | 'grill'
  | 'coffee_maker'
  | 'home_theater'
  | 'printer'
  | 'networking'
  | 'camera'
  | 'lighting'
  | 'dehumidifier'
  | 'freezer'
  | 'wine_cooler'
  | 'trash_compactor'
  | 'other';

export type EmailScanStatus = 'pending' | 'scanning' | 'completed' | 'failed';
export type PartnerType = 'realtor' | 'builder' | 'contractor' | 'property_manager' | 'other';
export type PartnerTier = 'basic' | 'premium' | 'platinum';
export type GiftStatus = 'pending_payment' | 'payment_failed' | 'created' | 'sent' | 'activated' | 'expired';
export type CommissionStatus = 'pending' | 'approved' | 'paid' | 'cancelled';
export type CommissionType = 'gift' | 'warranty_sale' | 'referral' | 'subscription';
export type WarrantyPurchaseStatus = 'pending' | 'active' | 'expired' | 'cancelled' | 'claimed';

// ============================================
// Warranty Claims
// ============================================

export interface WarrantyClaim {
  id: string;
  item_id: string;
  user_id: string;

  // Claim details
  claim_date: Date;
  issue_description: string | null;
  repair_description: string | null;

  // Financial impact
  repair_cost: number;
  amount_saved: number;
  out_of_pocket: number | null;

  // Status tracking
  status: string;
  filed_with: string | null;
  claim_number: string | null;

  // Meta
  notes: string | null;
  created_at: Date;
  updated_at: Date;
}

// ============================================
// Maintenance
// ============================================

export interface MaintenanceSchedule {
  id: string;
  category: ItemCategory;
  task_name: string;
  description: string | null;

  // Frequency
  frequency_months: number;
  frequency_label: string | null;

  // Task details
  estimated_duration_minutes: number | null;
  difficulty: 'easy' | 'medium' | 'hard';
  prevents_cost: number | null;

  // Resources
  how_to_url: string | null;
  video_url: string | null;
  tools_needed: string[] | null;

  // Meta
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

  // Task details
  task_name: string;
  completed_date: Date;

  // Details
  notes: string | null;
  duration_minutes: number | null;
  cost: number;

  // Meta
  created_at: Date;
}

// ============================================
// Email Scanning
// ============================================

export interface EmailScan {
  id: string;
  user_id: string;

  // Provider info
  provider: string;
  provider_email: string | null;

  // Scan details
  scan_date: Date;
  date_range_start: Date | null;
  date_range_end: Date | null;
  emails_scanned: number;
  receipts_found: number;
  items_imported: number;

  // Status
  status: EmailScanStatus;
  error_message: string | null;
  completed_at: Date | null;

  // Meta
  created_at: Date;
}

// ============================================
// Partner Program
// ============================================

export interface Partner {
  id: string;
  user_id: string;

  // Partner info
  partner_type: PartnerType;
  company_name: string | null;
  phone: string | null;
  website: string | null;

  // Branding
  brand_color: string | null;
  logo_url: string | null;
  subscription_tier: PartnerTier;

  // Settings
  default_message: string | null;
  default_premium_months: number;
  service_areas: string[];
  license_number: string | null;

  // Stripe Connect
  stripe_account_id: string | null;
  stripe_onboarded: boolean;

  // Status
  is_active: boolean;
  is_verified: boolean;

  // Meta
  created_at: Date;
  updated_at: Date;
}

export interface PartnerGift {
  id: string;
  partner_id: string;

  // Homebuyer info
  homebuyer_email: string;
  homebuyer_name: string;
  homebuyer_phone: string | null;
  home_address: string | null;
  closing_date: Date | null;

  // Gift details
  premium_months: number;
  custom_message: string | null;

  // Activation
  status: GiftStatus;
  is_activated: boolean;
  activation_code: string | null;
  activation_url: string | null;
  activated_at: Date | null;
  activated_user_id: string | null;
  expires_at: Date | null;

  // Billing
  amount_charged: number;
  stripe_charge_id: string | null;

  // Analytics
  email_opened_at: Date | null;
  app_download_at: Date | null;
  first_item_added_at: Date | null;

  // Meta
  created_at: Date;
  updated_at: Date;
}

export interface PartnerCommission {
  id: string;
  partner_id: string;

  // Commission details
  type: CommissionType;
  amount: number;
  description: string | null;

  // Status
  status: CommissionStatus;
  approved_at: Date | null;
  paid_at: Date | null;

  // References
  reference_id: string | null;
  reference_type: string | null;

  // Payout
  stripe_transfer_id: string | null;
  payout_method: string;

  // Meta
  created_at: Date;
  updated_at: Date;
}

// ============================================
// Extended Warranties
// ============================================

export interface WarrantyPurchase {
  id: string;
  item_id: string;
  user_id: string;

  // Provider details
  provider: string;
  plan_name: string;
  external_policy_id: string | null;

  // Coverage details
  duration_months: number;
  starts_at: Date;
  expires_at: Date;
  coverage_details: Record<string, any> | null;

  // Pricing
  price: number;
  deductible: number;
  claim_limit: number | null;

  // Commission tracking
  commission_amount: number | null;
  commission_rate: number | null;

  // Purchase details
  purchase_date: Date;
  stripe_payment_intent_id: string | null;

  // Status
  status: WarrantyPurchaseStatus;
  cancelled_at: Date | null;
  cancellation_reason: string | null;

  // Meta
  created_at: Date;
  updated_at: Date;
}

// ============================================
// Analytics
// ============================================

export interface UserAnalytics {
  id: string;
  user_id: string;

  // Engagement metrics
  last_active_at: Date | null;
  total_app_opens: number;
  total_sessions: number;
  avg_session_duration_seconds: number;

  // Health score
  current_health_score: number;
  health_score_history: Array<{ date: string; score: number }>;

  // Savings tracking
  total_warranty_savings: number;
  total_preventive_savings: number;
  total_claims_filed: number;
  total_maintenance_completed: number;

  // Feature usage
  email_scans_completed: number;
  items_added_manually: number;
  items_added_via_email: number;
  items_added_via_barcode: number;
  documents_uploaded: number;
  reports_generated: number;

  // Engagement flags
  has_activated_gift: boolean;
  has_completed_onboarding: boolean;
  has_added_first_item: boolean;
  has_scanned_email: boolean;
  has_filed_claim: boolean;

  // Meta
  updated_at: Date;
}

// ============================================
// Savings Feed
// ============================================

export interface SavingsFeedEntry {
  id: string;

  // Anonymized data
  user_city: string | null;
  user_state: string | null;

  // Savings details
  amount_saved: number;
  item_category: ItemCategory | null;
  claim_type: string | null;

  // Display
  display_text: string | null;

  // Meta
  created_at: Date;
}

// ============================================
// Dashboard Stats (from function)
// ============================================

export interface DashboardStats {
  total_value: number;
  total_items: number;
  active_warranties: number;
  expiring_soon: number;
  expired: number;
  total_repair_value: number;
  health_score: number;
}

// ============================================
// API Request/Response Types
// ============================================

export interface CreateWarrantyClaimDto {
  item_id: string;
  claim_date?: string;
  issue_description?: string;
  repair_description?: string;
  repair_cost: number;
  amount_saved: number;
  out_of_pocket?: number;
  status?: string;
  filed_with?: string;
  claim_number?: string;
  notes?: string;
}

export interface CreateMaintenanceHistoryDto {
  item_id: string;
  schedule_id?: string;
  task_name: string;
  completed_date?: string;
  notes?: string;
  duration_minutes?: number;
  cost?: number;
}
