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

    // Validate RevenueCat API key in production
    if (environment.isProduction && revenueCatApiKey.isEmpty) {
      throw StateError(
        'REVENUECAT_API_KEY must be set in production',
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
        'outlookRedirectUri: ${outlookRedirectUri.isNotEmpty ? outlookRedirectUri : "(empty)"}'
        ')';
  }
}
