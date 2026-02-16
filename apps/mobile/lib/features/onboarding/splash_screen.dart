import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/router/router.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// Splash screen — shown briefly while checking auth state.
///
/// Waits for BOTH the Lottie animation to finish AND the auth state
/// to resolve before navigating. This prevents race conditions where
/// navigation fires before auth is ready.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final void Function(AnimationStatus) _statusListener;
  late final ProviderSubscription<AsyncValue<User?>> _authSub;
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
        _fallbackTimer?.cancel();
        _animationComplete = true;
        _tryNavigate();
      }
    };
    _animController.addStatusListener(_statusListener);

    // Fallback: mark animation as complete after 3s even if Lottie fails
    _fallbackTimer = Timer(const Duration(milliseconds: 3000), () {
      if (!_animationComplete) {
        _animationComplete = true;
        _tryNavigate();
      }
    });

    // Listen for auth state resolution to trigger navigation
    _authSub = ref.listenManual(currentUserProvider, (_, __) => _tryNavigate());
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _authSub.close();
    _animController.removeStatusListener(_statusListener);
    _animController.dispose();
    super.dispose();
  }

  /// Navigate only when both animation is done AND auth state is resolved.
  void _tryNavigate() {
    if (_hasNavigated || !mounted || !_animationComplete) return;

    // Wait for currentUserProvider to finish loading
    final userAsync = ref.read(currentUserProvider);
    if (userAsync.isLoading) return; // will be called again via listener

    // If auth errored out, treat as signed-out and go to preview
    _hasNavigated = true;

    if (userAsync.hasError) {
      context.go(AppRoutes.preview);
      return;
    }

    final isAuthenticated = ref.read(isAuthenticatedProvider);
    if (isAuthenticated) {
      context.go(AppRoutes.dashboard);
    } else {
      context.go(AppRoutes.preview);
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
                    _tryNavigate();
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
