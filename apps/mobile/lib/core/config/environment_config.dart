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

  /// Supabase project URL.
  final String supabaseUrl;

  /// Supabase anonymous key for client authentication.
  final String supabaseAnonKey;

  /// Loki URL for log aggregation (optional).
  final String? lokiUrl;

  /// Whether to enable analytics tracking.
  final bool enableAnalytics;

  /// Whether to enable crash reporting and log shipping.
  final bool enableCrashReporting;

  /// Whether to enable debug logging.
  final bool enableDebugLogging;

  /// Base API URL (same as Supabase URL for now).
  String get baseApiUrl => supabaseUrl;

  /// Whether this is the production environment.
  bool get isProduction => environment.isProduction;

  /// Whether this is the development environment.
  bool get isDevelopment => environment.isDevelopment;

  /// Private constructor with validation.
  EnvironmentConfig._({
    required this.environment,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.lokiUrl,
    required this.enableAnalytics,
    required this.enableCrashReporting,
    required this.enableDebugLogging,
  }) {
    // Validate Supabase URL
    if (!supabaseUrl.startsWith('http://') &&
        !supabaseUrl.startsWith('https://')) {
      throw StateError(
        'Invalid SUPABASE_URL: must start with http:// or https://. Got: $supabaseUrl',
      );
    }

    // Validate Supabase anon key
    if (supabaseAnonKey.isEmpty || supabaseAnonKey == 'your-anon-key-here') {
      throw StateError(
        'Invalid SUPABASE_ANON_KEY: must not be empty or placeholder value',
      );
    }

    // Loki URL is optional - logs will just be local if not provided
  }

  /// Factory constructor that loads configuration from environment variables.
  ///
  /// This should be called after `dotenv.load()` has loaded the appropriate
  /// .env file for the current environment.
  factory EnvironmentConfig.fromEnvironment(Environment env) {
    // Get required values with validation
    final supabaseUrl = dotenv.get(
      'SUPABASE_URL',
      fallback: '',
    );

    final supabaseAnonKey = dotenv.get(
      'SUPABASE_ANON_KEY',
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
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
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
        'supabaseUrl: $supabaseUrl, '
        'enableAnalytics: $enableAnalytics, '
        'enableCrashReporting: $enableCrashReporting, '
        'enableDebugLogging: $enableDebugLogging'
        ')';
  }
}
