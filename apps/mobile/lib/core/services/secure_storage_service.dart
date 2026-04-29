import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
  // Default storage — backs up via iCloud Keychain on iOS. Used for items
  // that the user expects to roam across devices (push token,
  // biometric pref, active user id, device id).
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // S-HI-06: device-bound storage for the DB encryption key. The
  // `first_unlock_this_device` class is NOT iCloud-Keychain-eligible,
  // so an attacker who compromises the user's Apple ID can't restore
  // the encrypted SQLite file plus its key onto a fresh device. The
  // key has to be regenerated on a brand-new device, which means the
  // local DB cache is empty there until the user signs in and resyncs
  // — a small UX cost for a real security gain.
  static const _deviceBoundStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Storage keys
  static const _keyDeviceId = 'device_id';
  static const _keyPushToken = 'push_token';
  static const _keyBiometricEnabled = 'biometric_enabled';
  static const _keyDbEncryptionKey = 'db_encryption_key';
  static const _keyActiveUserId = 'active_user_id';
  static const _keyLastUnlockEpochMs = 'last_unlock_epoch_ms';

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

  // ---------------------------------------------------------------------------
  // Local DB encryption key (256-bit, generated on first launch)
  // ---------------------------------------------------------------------------

  /// Returns the persisted 256-bit DB encryption key, generating + storing
  /// one with a CSPRNG on first call. The key is base64-encoded for storage
  /// and decoded back to raw bytes on read.
  ///
  /// S-HI-06: stored in [_deviceBoundStorage] (KeychainAccessibility
  /// .first_unlock_this_device) so the key never replicates via iCloud
  /// Keychain. An attacker who compromises the user's Apple ID can't
  /// restore the encrypted DB plus its key onto a fresh device.
  static Future<Uint8List> getOrCreateDbEncryptionKey() async {
    try {
      final existing = await _deviceBoundStorage.read(key: _keyDbEncryptionKey);
      if (existing != null && existing.isNotEmpty) {
        return base64Decode(existing);
      }
      final rng = math.Random.secure();
      final bytes = Uint8List(32);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = rng.nextInt(256);
      }
      await _deviceBoundStorage.write(
        key: _keyDbEncryptionKey,
        value: base64Encode(bytes),
      );
      LoggingService.info('Generated new DB encryption key');
      return bytes;
    } catch (e, stack) {
      LoggingService.error('Failed to read/create DB encryption key', e, stack);
      rethrow;
    }
  }

  /// Wipe the DB encryption key (e.g. on sign-out, after the file is deleted).
  static Future<void> deleteDbEncryptionKey() async {
    try {
      await _deviceBoundStorage.delete(key: _keyDbEncryptionKey);
    } catch (e, stack) {
      LoggingService.error('Failed to delete DB encryption key', e, stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Active user (used to scope per-user DB files)
  // ---------------------------------------------------------------------------

  /// Persist the currently signed-in user id so background services (like
  /// the database opener) can derive a per-user DB filename.
  static Future<void> setActiveUserId(String? userId) async {
    try {
      if (userId == null || userId.isEmpty) {
        await _storage.delete(key: _keyActiveUserId);
      } else {
        await _storage.write(key: _keyActiveUserId, value: userId);
      }
    } catch (e, stack) {
      LoggingService.error('Failed to write active user id', e, stack);
    }
  }

  /// Read the currently signed-in user id (or null if signed out).
  static Future<String?> getActiveUserId() async {
    try {
      return await _storage.read(key: _keyActiveUserId);
    } catch (e, stack) {
      LoggingService.error('Failed to read active user id', e, stack);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Biometric lock — last unlock timestamp (for "lock after N seconds" gate)
  // ---------------------------------------------------------------------------

  /// Record the moment the biometric lock screen was last cleared.
  static Future<void> setLastUnlockTimestamp(DateTime when) async {
    try {
      await _storage.write(
        key: _keyLastUnlockEpochMs,
        value: when.millisecondsSinceEpoch.toString(),
      );
    } catch (e, stack) {
      LoggingService.error('Failed to write last unlock timestamp', e, stack);
    }
  }

  /// Read the last successful unlock timestamp (null if never unlocked).
  static Future<DateTime?> getLastUnlockTimestamp() async {
    try {
      final raw = await _storage.read(key: _keyLastUnlockEpochMs);
      if (raw == null || raw.isEmpty) return null;
      final ms = int.tryParse(raw);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (e, stack) {
      LoggingService.error('Failed to read last unlock timestamp', e, stack);
      return null;
    }
  }

  /// Clear all secure storage.
  ///
  /// Called on sign out to remove all sensitive data. S-HI-06: also clears
  /// the device-bound store so the DB encryption key isn't left behind
  /// when the user signs out.
  static Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      await _deviceBoundStorage.deleteAll();
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
