/// App limit constants (server-agnostic).

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
