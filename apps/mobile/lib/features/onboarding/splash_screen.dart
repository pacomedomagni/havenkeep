import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/router/router.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// Splash screen — shown briefly while checking auth state.
///
/// Shows the Lottie animation (or static logo fallback) while auth resolves.
/// Uses a simple two-phase approach:
/// 1. Wait for animation to finish (or 3s fallback)
/// 2. Navigate based on synchronous auth check (no async provider dependency)
///
/// This avoids the broadcast-stream race condition where authStateProvider
/// never emits and currentUserProvider stays in AsyncLoading forever.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final void Function(AnimationStatus) _statusListener;
  Timer? _fallbackTimer;
  bool _hasNavigated = false;
  bool _animationComplete = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _statusListener = (status) {
      if (status == AnimationStatus.completed) {
        debugPrint('[Splash] Animation completed');
        _fallbackTimer?.cancel();
        _animationComplete = true;
        _navigate();
      }
    };
    _animController.addStatusListener(_statusListener);

    // Fallback: mark animation as complete after 3s even if Lottie fails
    _fallbackTimer = Timer(const Duration(milliseconds: 3000), () {
      if (!_animationComplete) {
        debugPrint('[Splash] Fallback timer fired — animation did not complete');
        _animationComplete = true;
        _navigate();
      }
    });
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _animController.removeStatusListener(_statusListener);
    _animController.dispose();
    super.dispose();
  }

  /// Navigate based on synchronous auth state.
  ///
  /// Uses [isAuthenticatedProvider] which reads the API client's token
  /// directly — no dependency on the broadcast stream that may never emit.
  void _navigate() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final isAuthenticated = ref.read(isAuthenticatedProvider);
    debugPrint('[Splash] Navigating — isAuthenticated=$isAuthenticated');

    if (isAuthenticated) {
      context.go(AppRoutes.dashboard);
    } else {
      context.go(AppRoutes.welcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lottie animation with fallback
            SizedBox(
              width: 120,
              height: 120,
              child: Lottie.asset(
                'assets/lottie/splash_logo.json',
                controller: _animController,
                onLoaded: (composition) {
                  _animController.duration = composition.duration;
                  _animController.forward();
                },
                errorBuilder: (_, __, ___) {
                  // Fallback to static logo if Lottie file not found.
                  // Defer navigation to avoid calling setState/navigate during build.
                  _fallbackTimer?.cancel();
                  _animationComplete = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _navigate();
                  });
                  return const HavenKeepLogo(size: 80);
                },
              ),
            ),
            const SizedBox(height: HavenSpacing.md),
            const Text(
              'HavenKeep',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: HavenColors.textPrimary,
              ),
            ),
            const SizedBox(height: HavenSpacing.xs),
            const Text(
              'Your Warranties. Protected.',
              style: TextStyle(
                fontSize: 16,
                color: HavenColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
