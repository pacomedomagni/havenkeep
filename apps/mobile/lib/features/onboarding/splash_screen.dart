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
/// Displays a Lottie animation (with static fallback), then navigates
/// to Welcome (if not authenticated) or Dashboard (if authenticated).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Navigate after animation completes or fallback timer
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigate();
      }
    });

    // Fallback: navigate after 2.5s even if animation fails
    Future.delayed(const Duration(milliseconds: 2500), () {
      _navigate();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _navigate() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final isAuthenticated = ref.read(isAuthenticatedProvider);
    if (isAuthenticated) {
      context.go(AppRoutes.dashboard);
    } else {
      // Show preview screens for non-authenticated users
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
                  // Fallback to static logo if Lottie file not found
                  _navigate();
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
