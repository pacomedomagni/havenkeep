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
  }) {
    // Validate API base URL
    if (!apiBaseUrl.startsWith('http://') &&
        !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Invalid API_BASE_URL: must start with http:// or https://. Got: $apiBaseUrl',
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
    );
  }

  @override
  String toString() {
    return 'EnvironmentConfig('
        'environment: ${environment.name}, '
        'apiBaseUrl: $apiBaseUrl, '
        'enableAnalytics: $enableAnalytics, '
        'enableCrashReporting: $enableCrashReporting, '
        'enableDebugLogging: $enableDebugLogging'
        ')';
  }
}
