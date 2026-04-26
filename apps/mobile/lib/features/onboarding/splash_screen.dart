import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/router/router.dart';
import '../../core/services/logging_service.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// SharedPreferences key for the cached "user has at least one home"
/// answer. Lets the splash short-circuit to the right destination on
/// cold-start instead of waiting for the homes query to resolve, which
/// turns a 1.5-2s flash of splash into ~150ms (Ch05-F088).
const _kHasHomeCacheKey = 'splash_has_home_cached';

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
  Timer? _stuckTimer;
  bool _hasNavigated = false;
  bool _animationComplete = false;
  // Ch05-F098: surfaced when bootstrap stalls — usually the homes query
  // hanging on a flaky network. Tap-to-retry lets the user kick the loop
  // again without force-quitting the app.
  bool _bootstrapFailed = false;
  Object? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _statusListener = (status) {
      if (status == AnimationStatus.completed) {
        // Ch05-F075: route through the structured logger so splash
        // navigation drops into the same telemetry pipeline as the rest
        // of the app instead of being invisible to release builds.
        LoggingService.debug('Splash animation completed');
        _fallbackTimer?.cancel();
        _animationComplete = true;
        _navigate();
      }
    };
    _animController.addStatusListener(_statusListener);

    // Fallback: mark animation as complete after 3s even if Lottie fails
    _fallbackTimer = Timer(const Duration(milliseconds: 3000), () {
      if (!_animationComplete) {
        LoggingService.warn(
          'Splash fallback timer fired — Lottie did not complete',
        );
        _animationComplete = true;
        _navigate();
      }
    });
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _stuckTimer?.cancel();
    _animController.removeStatusListener(_statusListener);
    _animController.dispose();
    super.dispose();
  }

  /// Show the retry surface if bootstrap hasn't navigated within
  /// [_kBootstrapStuckThreshold] of starting. Prevents the user from
  /// staring at a frozen splash if `hasHomeProvider` never resolves.
  static const Duration _kBootstrapStuckThreshold = Duration(seconds: 12);

  /// Navigate based on synchronous auth state.
  ///
  /// Uses [isAuthenticatedProvider] which reads the API client's token
  /// directly — no dependency on the broadcast stream that may never emit.
  /// For authenticated users we must also know whether they have any
  /// homes before we navigate, otherwise the router would bounce them
  /// back to the splash and leave them stranded (C101).
  Future<void> _navigate() async {
    if (_hasNavigated || !mounted) return;

    _stuckTimer?.cancel();
    _stuckTimer = Timer(_kBootstrapStuckThreshold, () {
      if (!_hasNavigated && mounted) {
        LoggingService.warn('Splash bootstrap stuck — surfacing tap-to-retry');
        setState(() => _bootstrapFailed = true);
      }
    });

    try {
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      LoggingService.debug(
        'Splash navigating',
        {'isAuthenticated': isAuthenticated},
      );

      if (!isAuthenticated) {
        _hasNavigated = true;
        _stuckTimer?.cancel();
        context.go(AppRoutes.welcome);
        return;
      }

      // Ch05-F088: prefer the cached answer so cold-start hits its
      // destination in ~150ms instead of waiting on the homes query.
      // Either a fresh API value (already resolved) or a cached boolean
      // is fine — the homes provider keeps refreshing in the background
      // and the router itself re-checks when the user lands.
      final hasHome = await _resolveHasHome();
      if (!mounted) return;
      _hasNavigated = true;
      _stuckTimer?.cancel();
      context.go(hasHome ? AppRoutes.dashboard : AppRoutes.firstAction);
    } catch (err, stack) {
      LoggingService.error('Splash bootstrap failed', err, stack);
      if (mounted) {
        setState(() {
          _bootstrapFailed = true;
          _bootstrapError = err;
        });
      }
    }
  }

  /// Tap-to-retry handler. Reset the failed flag, invalidate the providers
  /// that gate navigation, and re-enter `_navigate` so the user can break
  /// out of a transient connectivity stall without restarting the app.
  void _retryBootstrap() {
    if (!mounted) return;
    setState(() {
      _bootstrapFailed = false;
      _bootstrapError = null;
    });
    ref.invalidate(hasHomeProvider);
    _navigate();
  }

  /// Read [hasHomeProvider] if it already has a value; otherwise fall
  /// back to the cached boolean (Ch05-F088) and only block on the
  /// network when we've never recorded an answer for this install.
  Future<bool> _resolveHasHome() async {
    final initial = ref.read(hasHomeProvider).valueOrNull;
    if (initial != null) {
      // Persist the latest answer so the next cold-start can use it
      // without waiting on the network.
      _cacheHasHome(initial);
      return initial;
    }

    final cached = await _loadCachedHasHome();
    if (cached != null) {
      // Kick off a background revalidation so the cache stays honest
      // for the next launch — fire and forget; the router refreshes
      // on landing and any divergence will be reconciled there.
      unawaited(_refreshHasHomeCache());
      return cached;
    }

    final completer = Completer<bool>();
    final sub = ref.listenManual<AsyncValue<bool>>(
      hasHomeProvider,
      (_, next) {
        final value = next.valueOrNull;
        if (value != null && !completer.isCompleted) {
          completer.complete(value);
        }
      },
      fireImmediately: false,
    );

    try {
      final value = await completer.future;
      await _cacheHasHome(value);
      return value;
    } finally {
      sub.close();
    }
  }

  Future<bool?> _loadCachedHasHome() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kHasHomeCacheKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheHasHome(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHasHomeCacheKey, value);
    } catch (_) {
      // Best-effort; nothing depends on the write succeeding.
    }
  }

  Future<void> _refreshHasHomeCache() async {
    final completer = Completer<bool>();
    final sub = ref.listenManual<AsyncValue<bool>>(
      hasHomeProvider,
      (_, next) {
        final value = next.valueOrNull;
        if (value != null && !completer.isCompleted) {
          completer.complete(value);
        }
      },
      fireImmediately: false,
    );
    try {
      final value = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      await _cacheHasHome(value);
    } finally {
      sub.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ch05-F083: respect the OS "Reduce motion" toggle. When the user has
    // animations disabled (vestibular triggers, screen-reader heuristics)
    // we skip Lottie entirely and short-circuit straight to navigation
    // so we don't strand them on a frozen splash.
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations && !_animationComplete) {
      _fallbackTimer?.cancel();
      _animationComplete = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
    }

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
              child: disableAnimations
                  ? const HavenKeepLogo(size: 80)
                  : Lottie.asset(
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
            if (_bootstrapFailed) ...[
              const SizedBox(height: HavenSpacing.xl),
              const Text(
                "Couldn't reach HavenKeep.",
                style: TextStyle(
                  fontSize: 14,
                  color: HavenColors.textSecondary,
                ),
              ),
              if (_bootstrapError != null) ...[
                const SizedBox(height: HavenSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.lg),
                  child: Text(
                    _bootstrapError.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HavenColors.textTertiary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: HavenSpacing.md),
              OutlinedButton.icon(
                onPressed: _retryBootstrap,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tap to retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.primary,
                  side: const BorderSide(color: HavenColors.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
