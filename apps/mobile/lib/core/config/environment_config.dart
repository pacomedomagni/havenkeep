import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'environment.dart';

/// Environment-specific configuration for the HavenKeep app.
///
/// This class loads configuration from .env files and validates all required
/// values at app startup. If any configuration is invalid or missing, the app
/// will fail fast with a clear error message.
class EnvironmentConfig {
  /// The current environment (development, staging, or production).
  final Environment environment;

  /// Base URL for the HavenKeep Express API.
  final String apiBaseUrl;

  /// Loki URL for log aggregation (optional).
  final String? lokiUrl;

  /// Whether to enable analytics tracking.
  final bool enableAnalytics;

  /// Whether to enable crash reporting and log shipping.
  final bool enableCrashReporting;

  /// Whether to enable debug logging.
  final bool enableDebugLogging;

  /// RevenueCat API key for in-app purchases.
  final String revenueCatApiKey;

  /// Outlook OAuth client ID (optional, for email scanning).
  final String outlookClientId;

  /// Outlook OAuth tenant (optional, default: common).
  final String outlookTenant;

  /// Outlook OAuth redirect URI (optional).
  final String outlookRedirectUri;

  /// Firebase Android API key (optional — Firebase is skipped if empty).
  final String firebaseAndroidApiKey;

  /// Firebase iOS API key (optional — Firebase is skipped if empty).
  final String firebaseIosApiKey;

  /// Firebase project ID (optional).
  final String firebaseProjectId;

  /// Firebase Android app ID (optional).
  final String firebaseAndroidAppId;

  /// Firebase iOS app ID (optional).
  final String firebaseIosAppId;

  /// Firebase Cloud Messaging sender ID (optional).
  final String firebaseMessagingSenderId;

  /// Firebase Storage bucket (optional).
  final String firebaseStorageBucket;

  /// Firebase iOS bundle ID (optional).
  final String firebaseIosBundleId;

  /// Base URL for the app's public website.
  final String appUrl;

  /// Support email address.
  final String supportEmail;

  /// Whether this is the production environment.
  bool get isProduction => environment.isProduction;

  /// Whether this is the development environment.
  bool get isDevelopment => environment.isDevelopment;

  /// Private constructor with validation.
  EnvironmentConfig._({
    required this.environment,
    required this.apiBaseUrl,
    this.lokiUrl,
    required this.enableAnalytics,
    required this.enableCrashReporting,
    required this.enableDebugLogging,
    required this.revenueCatApiKey,
    required this.outlookClientId,
    required this.outlookTenant,
    required this.outlookRedirectUri,
    required this.firebaseAndroidApiKey,
    required this.firebaseIosApiKey,
    required this.firebaseProjectId,
    required this.firebaseAndroidAppId,
    required this.firebaseIosAppId,
    required this.firebaseMessagingSenderId,
    required this.firebaseStorageBucket,
    required this.firebaseIosBundleId,
    required this.appUrl,
    required this.supportEmail,
  }) {
    // Validate API base URL is present
    if (apiBaseUrl.isEmpty) {
      throw StateError(
        'API_BASE_URL is required but was not set in .env file',
      );
    }

    // Validate API base URL format
    if (!apiBaseUrl.startsWith('http://') &&
        !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Invalid API_BASE_URL: must start with http:// or https://. Got: $apiBaseUrl',
      );
    }

    // Warn about missing RevenueCat API key in production (premium features won't work)
    if (environment.isProduction && revenueCatApiKey.isEmpty) {
      debugPrint(
        '[EnvironmentConfig] WARNING: REVENUECAT_API_KEY is not set in production. '
        'Premium features will be unavailable.',
      );
    }
  }

  /// Factory constructor that loads configuration from environment variables.
  ///
  /// This should be called after `dotenv.load()` has loaded the appropriate
  /// .env file for the current environment.
  factory EnvironmentConfig.fromEnvironment(Environment env) {
    // Get required values with validation
    final apiBaseUrl = dotenv.get(
      'API_BASE_URL',
      fallback: '',
    );

    // Get optional values
    final lokiUrl = dotenv.maybeGet('LOKI_URL');

    // Get RevenueCat API key
    final revenueCatApiKey = dotenv.get(
      'REVENUECAT_API_KEY',
      fallback: '',
    );

    final outlookClientId = dotenv.get(
      'OUTLOOK_CLIENT_ID',
      fallback: '',
    );
    final outlookTenant = dotenv.get(
      'OUTLOOK_TENANT',
      fallback: 'common',
    );
    final outlookRedirectUri = dotenv.get(
      'OUTLOOK_REDIRECT_URI',
      fallback: '',
    );

    // Firebase configuration (optional — Firebase is skipped when keys are empty)
    final firebaseAndroidApiKey = dotenv.get(
      'FIREBASE_ANDROID_API_KEY',
      fallback: '',
    );
    final firebaseIosApiKey = dotenv.get(
      'FIREBASE_IOS_API_KEY',
      fallback: '',
    );
    final firebaseProjectId = dotenv.get(
      'FIREBASE_PROJECT_ID',
      fallback: '',
    );
    final firebaseAndroidAppId = dotenv.get(
      'FIREBASE_ANDROID_APP_ID',
      fallback: '',
    );
    final firebaseIosAppId = dotenv.get(
      'FIREBASE_IOS_APP_ID',
      fallback: '',
    );
    final firebaseMessagingSenderId = dotenv.get(
      'FIREBASE_MESSAGING_SENDER_ID',
      fallback: '',
    );
    final firebaseStorageBucket = dotenv.get(
      'FIREBASE_STORAGE_BUCKET',
      fallback: '',
    );
    final firebaseIosBundleId = dotenv.get(
      'FIREBASE_IOS_BUNDLE_ID',
      fallback: 'com.flokou.havenkeep',
    );

    // App URL and support email
    final appUrl = dotenv.get(
      'APP_URL',
      fallback: 'https://havenkeep.app',
    );
    final supportEmail = dotenv.get(
      'SUPPORT_EMAIL',
      fallback: 'support@havenkeep.app',
    );

    // Environment-specific defaults
    final enableAnalytics = env.isProduction;
    final enableCrashReporting = !env.isDevelopment;
    final enableDebugLogging = env.isDevelopment;

    return EnvironmentConfig._(
      environment: env,
      apiBaseUrl: apiBaseUrl,
      lokiUrl: lokiUrl,
      enableAnalytics: enableAnalytics,
      enableCrashReporting: enableCrashReporting,
      enableDebugLogging: enableDebugLogging,
      revenueCatApiKey: revenueCatApiKey,
      outlookClientId: outlookClientId,
      outlookTenant: outlookTenant,
      outlookRedirectUri: outlookRedirectUri,
      firebaseAndroidApiKey: firebaseAndroidApiKey,
      firebaseIosApiKey: firebaseIosApiKey,
      firebaseProjectId: firebaseProjectId,
      firebaseAndroidAppId: firebaseAndroidAppId,
      firebaseIosAppId: firebaseIosAppId,
      firebaseMessagingSenderId: firebaseMessagingSenderId,
      firebaseStorageBucket: firebaseStorageBucket,
      firebaseIosBundleId: firebaseIosBundleId,
      appUrl: appUrl,
      supportEmail: supportEmail,
    );
  }

  @override
  String toString() {
    return 'EnvironmentConfig('
        'environment: ${environment.name}, '
        'apiBaseUrl: $apiBaseUrl, '
        'enableAnalytics: $enableAnalytics, '
        'enableCrashReporting: $enableCrashReporting, '
        'enableDebugLogging: $enableDebugLogging, '
        'revenueCatApiKey: ${revenueCatApiKey.isNotEmpty ? "***" : "(empty)"}, '
        'outlookClientId: ${outlookClientId.isNotEmpty ? "***" : "(empty)"}, '
        'outlookTenant: $outlookTenant, '
        'outlookRedirectUri: ${outlookRedirectUri.isNotEmpty ? outlookRedirectUri : "(empty)"}, '
        'firebaseProjectId: ${firebaseProjectId.isNotEmpty ? firebaseProjectId : "(empty)"}, '
        'appUrl: $appUrl, '
        'supportEmail: $supportEmail'
        ')';
  }
}
