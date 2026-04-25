import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/biometric_service.dart';
import '../../core/services/secure_storage_service.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// Full-screen overlay that blocks all UI behind it until the user
/// re-authenticates via the platform biometric SDK. Pushed by
/// [BiometricLockObserver] whenever the app returns from background and
/// the user has biometric unlock enabled.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _attempting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Auto-prompt as soon as the route mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_attempting) return;
    setState(() {
      _attempting = true;
      _failed = false;
    });

    final ok = await BiometricService.authenticate();
    if (!mounted) return;

    if (ok) {
      await SecureStorageService.setLastUnlockTimestamp(DateTime.now());
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _attempting = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent system back from dismissing the lock — the only way out
      // is a successful biometric prompt.
      canPop: false,
      child: Scaffold(
        backgroundColor: HavenColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const HavenKeepLogo(size: 64),
                const SizedBox(height: HavenSpacing.lg),
                const Text(
                  'HavenKeep is locked',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HavenSpacing.sm),
                Text(
                  _failed
                      ? 'Authentication failed. Please try again.'
                      : 'Use biometrics to unlock and continue.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: HavenColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HavenSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _attempting ? null : _authenticate,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(_attempting ? 'Verifying…' : 'Unlock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
