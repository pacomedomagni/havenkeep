/// Supabase table, view, bucket, and function name constants.
///
/// Using constants prevents typos and enables IDE autocomplete.

// ============================================
// TABLE NAMES
// ============================================

const kUsersTable = 'users';
const kHomesTable = 'homes';
const kItemsTable = 'items';
const kDocumentsTable = 'documents';
const kNotificationsTable = 'notifications';
const kReferralPartnersTable = 'referral_partners';
const kReferralsTable = 'referrals';
const kAffiliateConversionsTable = 'affiliate_conversions';
const kNotificationPreferencesTable = 'notification_preferences';
const kOfflineQueueTable = 'offline_queue';
const kCategoryDefaultsTable = 'category_defaults';
const kBrandSuggestionsTable = 'brand_suggestions';

// ============================================
// VIEW NAMES
// ============================================

const kItemsWithStatusView = 'items_with_status';
const kDashboardSummaryView = 'dashboard_summary';
const kNeedsAttentionView = 'needs_attention';

// ============================================
// FUNCTION NAMES
// ============================================

const kGetWarrantyStatusFn = 'get_warranty_status';
const kCountActiveItemsFn = 'count_active_items';

// ============================================
// STORAGE BUCKETS
// ============================================

const kDocumentsBucket = 'documents';

// ============================================
// APP LIMITS
// ============================================

/// Maximum number of non-archived items on the free plan.
const kFreePlanItemLimit = 25;

/// Maximum document storage on free plan (200 MB).
const kFreePlanStorageLimit = 200 * 1024 * 1024; // bytes

/// Maximum document storage on premium plan (2 GB).
const kPremiumPlanStorageLimit = 2 * 1024 * 1024 * 1024; // bytes

/// Maximum single file upload size (50 MB).
const kMaxFileUploadSize = 50 * 1024 * 1024; // bytes

/// Warranty "expiring soon" threshold in days.
const kExpiringThresholdDays = 90;

/// Maximum items shown in "Needs Attention" on dashboard.
const kNeedsAttentionLimit = 3;
