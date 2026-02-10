/// Environment configuration for HavenKeep mobile app.
///
/// Defines the three environments (development, staging, production) and
/// provides type-safe access to environment-specific settings.

enum Environment {
  development,
  staging,
  production;

  /// Returns true if this is the production environment.
  bool get isProduction => this == Environment.production;

  /// Returns true if this is the development environment.
  bool get isDevelopment => this == Environment.development;

  /// Returns true if this is the staging environment.
  bool get isStaging => this == Environment.staging;

  /// Returns the environment name as a string.
  String get name {
    switch (this) {
      case Environment.development:
        return 'development';
      case Environment.staging:
        return 'staging';
      case Environment.production:
        return 'production';
    }
  }

  /// Parse environment from string.
  static Environment fromString(String value) {
    switch (value.toLowerCase()) {
      case 'development':
      case 'dev':
        return Environment.development;
      case 'staging':
      case 'stage':
        return Environment.staging;
      case 'production':
      case 'prod':
        return Environment.production;
      default:
        throw ArgumentError('Unknown environment: $value');
    }
  }
}
