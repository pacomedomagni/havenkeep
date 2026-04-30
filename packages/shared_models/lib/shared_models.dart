/// HavenKeep shared data models.
///
/// This package contains all data models used across the HavenKeep app:
/// - User, Home, Item, Document
/// - AppNotification, NotificationPreferences
/// - ReferralPartner, Referral, AffiliateConversion
/// - CategoryDefault, BrandSuggestion, Tip
/// - Partner, PartnerGift, PartnerCommission
/// - WarrantyClaim, WarrantyPurchase
/// - MaintenanceSchedule + history
/// - EmailScan, ContactSubmission
/// - OfflineQueueEntry
/// - All enums (Category, Room, WarrantyType, WarrantyStatus, etc.)
library shared_models;

export 'src/enums.dart';
export 'src/user.dart';
export 'src/home.dart';
export 'src/item.dart';
export 'src/document.dart';
export 'src/app_notification.dart';
export 'src/referral_partner.dart';
export 'src/referral.dart';
export 'src/affiliate_conversion.dart';
export 'src/notification_preferences.dart';
export 'src/offline_queue_entry.dart';
export 'src/category_default.dart';
export 'src/brand_suggestion.dart';
export 'src/receipt_scan_result.dart';
export 'src/barcode_lookup_result.dart';
export 'src/contact_submission.dart' show ContactSubmission;
export 'src/tip.dart' show Tip;
export 'src/partner.dart' show Partner, PartnerSubscriptionTier, PartnerStatus;
export 'src/warranty_claim.dart' show WarrantyClaim, ClaimStatus;
export 'src/maintenance.dart'
    show
        MaintenanceSchedule,
        MaintenanceHistory,
        MaintenanceDifficulty,
        MaintenanceDueTask,
        MaintenanceDueItem,
        MaintenanceDueSummary,
        MaintenanceSummaryState;
export 'src/warranty_purchase.dart' show WarrantyPurchase, WarrantyPurchaseStatus;
export 'src/email_scan.dart' show EmailScan, EmailScanStatus;
export 'src/partner_gift.dart' show PartnerGift, PartnerGiftStatus;
export 'src/partner_commission.dart'
    show
        PartnerCommission,
        PartnerCommissionType,
        PartnerCommissionStatus,
        PartnerCommissionReferenceType,
        PartnerCommissionPayoutMethod;
// Audit Ch08-D018: shared funnel for unknown-enum drift. Exposed so the
// mobile bootstrap can plug in a custom transport (Firebase Crashlytics
// breadcrumb, custom HTTP collector, etc.) on top of the always-on
// `dart:developer.log` sink. Individual enums import _unknown_enum_log.dart
// directly (it lives next to them in src/) and call logUnknownEnumValue
// on a miss.
export 'src/_unknown_enum_log.dart' show registerUnknownEnumReporter;
