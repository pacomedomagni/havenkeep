/// HavenKeep shared data models.
///
/// This package contains all data models used across the HavenKeep app:
/// - User, Home, Item, Document
/// - AppNotification, NotificationPreferences
/// - ReferralPartner, Referral, AffiliateConversion
/// - CategoryDefault, BrandSuggestion
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
