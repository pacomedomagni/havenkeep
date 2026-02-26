import 'package:local_auth/local_auth.dart';

import 'logging_service.dart';
import 'secure_storage_service.dart';

/// Biometric authentication service.
///
/// Wraps the `local_auth` plugin to provide fingerprint / Face ID
/// authentication gated by a user-controlled preference stored in
/// [SecureStorageService].
class BiometricService {
  static final _auth = LocalAuthentication();

  /// Whether the device supports biometric authentication.
  ///
  /// Returns `true` only when the hardware is present **and** the device
  /// has at least one enrolled biometric credential.
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (e, stack) {
      LoggingService.error('Failed to check biometric availability', e, stack);
      return false;
    }
  }

  /// Returns the list of enrolled biometric types (fingerprint, face, iris).
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e, stack) {
      LoggingService.error('Failed to get available biometrics', e, stack);
      return [];
    }
  }

  /// Prompt the user for biometric authentication.
  ///
  /// Returns `true` when authentication succeeds.
  static Future<bool> authenticate() async {
    try {
      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Unlock HavenKeep',
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      return didAuthenticate;
    } catch (e, stack) {
      LoggingService.error('Biometric authentication failed', e, stack);
      return false;
    }
  }

  /// Enable or disable the biometric unlock preference.
  ///
  /// Delegates persistence to [SecureStorageService].
  static Future<void> setBiometricEnabled(bool enabled) async {
    await SecureStorageService.setBiometricEnabled(enabled);
  }

  /// Whether the user has opted in to biometric unlock.
  static Future<bool> isBiometricEnabled() async {
    return SecureStorageService.isBiometricEnabled();
  }
}
