// ============================================
// Database Types for HavenKeep
// Auto-generated from PostgreSQL schema
// ============================================

export type UserPlan = 'free' | 'premium';
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
  | 'other';

export type ItemRoom =
  | 'kitchen'
  | 'bathroom'
  | 'master_bedroom'
  | 'bedroom'
  | 'living_room'
  | 'dining_room'
  | 'laundry'
  | 'garage'
  | 'basement'
  | 'attic'
  | 'outdoor'
  | 'hvac_utility'
  | 'office'
  | 'other';

export type WarrantyType = 'manufacturer' | 'extended' | 'store' | 'home_warranty';
export type HomeType = 'house' | 'condo' | 'apartment' | 'townhouse' | 'other';
export type DocumentType = 'receipt' | 'warranty_card' | 'manual' | 'invoice' | 'other';

// New types for enhanced features
export type EmailScanStatus = 'pending' | 'scanning' | 'completed' | 'failed';
export type PartnerType = 'realtor' | 'builder' | 'contractor' | 'other';
export type PartnerTier = 'basic' | 'premium' | 'platinum';
export type GiftStatus = 'created' | 'sent' | 'activated' | 'expired';
export type CommissionStatus = 'pending' | 'approved' | 'paid' | 'cancelled';
export type CommissionType = 'gift' | 'warranty_sale' | 'referral' | 'subscription';
export type WarrantyPurchaseStatus = 'active' | 'expired' | 'cancelled' | 'claimed';
export type NotificationType =
  | 'warranty_expiring'
  | 'warranty_expired'
  | 'maintenance_due'
  | 'claim_opportunity'
  | 'health_score_update'
  | 'gift_received'
  | 'partner_commission'
  | 'system';

// ============================================
// Core Tables
// ============================================

export interface User {
  id: string;
  email: string;
  password_hash: string | null;
  full_name: string;
  avatar_url: string | null;
  plan: UserPlan;
  plan_expires_at: Date | null;
  stripe_customer_id: string | null;
  is_admin: boolean;
  email_verified: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface Home {
  id: string;
  user_id: string;
  name: string;
  address: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  home_type: HomeType;
  move_in_date: Date | null;
  created_at: Date;
  updated_at: Date;
}

export interface Item {
  id: string;
  home_id: string;
  user_id: string;

  // Product info
  name: string;
  brand: string | null;
  model_number: string | null;
  serial_number: string | null;
  category: ItemCategory;
  room: ItemRoom | null;
  product_image_url: string | null;
  barcode: string | null;

  // Purchase info
  purchase_date: Date;
  store: string | null;
  price: number | null;

  // Warranty info
  warranty_months: number;
  warranty_end_date: Date;
  warranty_type: WarrantyType;
  warranty_provider: string | null;

  // Enhanced fields
  estimated_repair_cost: number | null;
  expected_lifespan_years: number | null;
  installation_date: Date | null;
  last_maintenance_date: Date | null;
  next_maintenance_due: Date | null;

  // Meta
  notes: string | null;
  is_archived: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface Document {
  id: string;
  item_id: string;
  user_id: string;
  type: DocumentType;
  file_url: string;
  file_name: string;
  file_size: number;
  mime_type: string;
  thumbnail_url: string | null;
  created_at: Date;
}

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
// Notifications
// ============================================

export interface NotificationTemplate {
  id: string;
  name: string;
  type: NotificationType;

  // Template content
  title_template: string;
  body_template: string;

  // Actions
  actions: Array<{
    id: string;
    title: string;
    icon: string;
  }>;

  // Settings
  is_active: boolean;
  priority: number;

  // Meta
  created_at: Date;
  updated_at: Date;
}

export interface NotificationHistory {
  id: string;
  user_id: string;
  template_id: string | null;

  // Related entities
  item_id: string | null;
  gift_id: string | null;

  // Content
  type: NotificationType;
  title: string;
  body: string;
  data: Record<string, any>;

  // Tracking
  sent_at: Date;
  delivered_at: Date | null;
  opened_at: Date | null;
  action_taken: string | null;
  action_taken_at: Date | null;

  // Platform
  platform: string | null;
  fcm_message_id: string | null;

  // Meta
  created_at: Date;
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

export interface CreateEmailScanDto {
  provider: 'gmail' | 'outlook';
  access_token: string;
  date_range_start?: string;
  date_range_end?: string;
}

export interface CreatePartnerGiftDto {
  homebuyer_email: string;
  homebuyer_name: string;
  homebuyer_phone?: string;
  home_address?: string;
  closing_date?: string;
  premium_months?: number;
  custom_message?: string;
}

export interface ExtendedWarrantyQuoteRequest {
  item_id: string;
}

export interface ExtendedWarrantyQuote {
  provider: string;
  logo: string;
  rating: number;
  plans: Array<{
    name: string;
    duration: number;
    price: number;
    coverage: string[];
    deductible: number;
    claim_limit: number;
  }>;
}
