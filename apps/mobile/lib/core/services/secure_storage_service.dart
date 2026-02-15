import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'logging_service.dart';

/// Secure storage service for sensitive data.
///
/// Uses platform-specific secure storage:
/// - iOS: Keychain
/// - Android: EncryptedSharedPreferences
///
/// Store only truly sensitive data here (auth tokens, encryption keys).
/// Use regular SharedPreferences for non-sensitive settings.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Storage keys
  static const _keyRefreshToken = 'refresh_token';
  static const _keyAccessToken = 'access_token';
  static const _keyDeviceId = 'device_id';
  static const _keyPushToken = 'push_token';
  static const _keyBiometricEnabled = 'biometric_enabled';

  /// Save refresh token securely.
  ///
  /// Called after successful authentication.
  @Deprecated('Auth tokens are managed by ApiClient. Use ApiClient.saveTokens/clearTokens instead.')
  static Future<void> saveRefreshToken(String token) async {
    try {
      await _storage.write(key: _keyRefreshToken, value: token);
      LoggingService.debug('Refresh token saved to secure storage');
    } catch (e, stack) {
      LoggingService.error('Failed to save refresh token', e, stack);
      rethrow;
    }
  }

  /// Retrieve refresh token.
  ///
  /// Returns null if not found or error occurs.
  @Deprecated('Auth tokens are managed by ApiClient. Use ApiClient.saveTokens/clearTokens instead.')
  static Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefreshToken);
    } catch (e, stack) {
      LoggingService.error('Failed to read refresh token', e, stack);
      return null;
    }
  }

  /// Delete refresh token.
  ///
  /// Called on sign out.
  @Deprecated('Auth tokens are managed by ApiClient. Use ApiClient.saveTokens/clearTokens instead.')
  static Future<void> deleteRefreshToken() async {
    try {
      await _storage.delete(key: _keyRefreshToken);
      LoggingService.debug('Refresh token deleted from secure storage');
    } catch (e, stack) {
      LoggingService.error('Failed to delete refresh token', e, stack);
    }
  }

  /// Save access token securely.
  @Deprecated('Auth tokens are managed by ApiClient. Use ApiClient.saveTokens/clearTokens instead.')
  static Future<void> saveAccessToken(String token) async {
    try {
      await _storage.write(key: _keyAccessToken, value: token);
    } catch (e, stack) {
      LoggingService.error('Failed to save access token', e, stack);
      rethrow;
    }
  }

  /// Retrieve access token.
  @Deprecated('Auth tokens are managed by ApiClient. Use ApiClient.saveTokens/clearTokens instead.')
  static Future<String?> getAccessToken() async {
    try {
      return await _storage.read(key: _keyAccessToken);
    } catch (e, stack) {
      LoggingService.error('Failed to read access token', e, stack);
      return null;
    }
  }

  /// Delete access token.
  @Deprecated('Auth tokens are managed by ApiClient. Use ApiClient.saveTokens/clearTokens instead.')
  static Future<void> deleteAccessToken() async {
    try {
      await _storage.delete(key: _keyAccessToken);
    } catch (e, stack) {
      LoggingService.error('Failed to delete access token', e, stack);
    }
  }

  /// Save device ID for push notifications.
  ///
  /// Device ID persists across app reinstalls (where possible).
  static Future<void> saveDeviceId(String deviceId) async {
    try {
      await _storage.write(key: _keyDeviceId, value: deviceId);
      LoggingService.debug('Device ID saved', {'deviceId': deviceId});
    } catch (e, stack) {
      LoggingService.error('Failed to save device ID', e, stack);
    }
  }

  /// Retrieve device ID.
  static Future<String?> getDeviceId() async {
    try {
      return await _storage.read(key: _keyDeviceId);
    } catch (e, stack) {
      LoggingService.error('Failed to read device ID', e, stack);
      return null;
    }
  }

  /// Save FCM push token.
  static Future<void> savePushToken(String token) async {
    try {
      await _storage.write(key: _keyPushToken, value: token);
      LoggingService.debug('Push token saved');
    } catch (e, stack) {
      LoggingService.error('Failed to save push token', e, stack);
    }
  }

  /// Retrieve FCM push token.
  static Future<String?> getPushToken() async {
    try {
      return await _storage.read(key: _keyPushToken);
    } catch (e, stack) {
      LoggingService.error('Failed to read push token', e, stack);
      return null;
    }
  }

  /// Delete push token.
  static Future<void> deletePushToken() async {
    try {
      await _storage.delete(key: _keyPushToken);
    } catch (e, stack) {
      LoggingService.error('Failed to delete push token', e, stack);
    }
  }

  /// Save biometric authentication preference.
  static Future<void> setBiometricEnabled(bool enabled) async {
    try {
      await _storage.write(
        key: _keyBiometricEnabled,
        value: enabled.toString(),
      );
      LoggingService.info('Biometric authentication ${enabled ? 'enabled' : 'disabled'}');
    } catch (e, stack) {
      LoggingService.error('Failed to save biometric preference', e, stack);
    }
  }

  /// Check if biometric authentication is enabled.
  static Future<bool> isBiometricEnabled() async {
    try {
      final value = await _storage.read(key: _keyBiometricEnabled);
      return value == 'true';
    } catch (e, stack) {
      LoggingService.error('Failed to read biometric preference', e, stack);
      return false;
    }
  }

  /// Clear all secure storage.
  ///
  /// Called on sign out to remove all sensitive data.
  static Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      LoggingService.info('Secure storage cleared');
    } catch (e, stack) {
      LoggingService.error('Failed to clear secure storage', e, stack);
    }
  }

  /// Check if secure storage is available and working.
  ///
  /// Useful for debugging storage issues.
  static Future<bool> isAvailable() async {
    try {
      // Try to write and read a test value
      const testKey = '_test_key';
      const testValue = 'test';

      await _storage.write(key: testKey, value: testValue);
      final readValue = await _storage.read(key: testKey);
      await _storage.delete(key: testKey);

      return readValue == testValue;
    } catch (e, stack) {
      LoggingService.error('Secure storage not available', e, stack);
      return false;
    }
  }
}
