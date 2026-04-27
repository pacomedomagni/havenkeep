import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'core/config/environment.dart';
import 'core/config/environment_config.dart';
import 'core/config/firebase_options.dart';
import 'core/database/database.dart';
import 'core/router/router.dart';
import 'core/services/app_lifecycle_service.dart';
import 'core/services/app_prefs_service.dart';
import 'core/services/auto_archive_service.dart';
import 'core/services/biometric_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/logging_service.dart';
import 'core/services/notification_display_service.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/secure_storage_service.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/demo_mode_provider.dart';
import 'core/providers/premium_provider.dart';
import 'features/onboarding/biometric_lock_screen.dart';

Future<void> main() async {
  // Run inside a guarded zone to catch any remaining unhandled errors.
  // WidgetsFlutterBinding.ensureInitialized() must be called inside the same
  // zone as runApp() to avoid the "Zone mismatch" assertion.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Portrait-first on phones, but allow landscape on tablets so the
      // responsive layouts we ship can actually shine. Flutter itself
      // applies these preferences only where the platform respects them.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // Set system UI overlay style to match dark theme
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: HavenColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ));

      // Determine environment from build flavor (defaults to development)
      const flavorString = String.fromEnvironment('FLAVOR', defaultValue: 'development');
      final environment = Environment.fromString(flavorString);

      // Load environment-specific configuration
      final envFileName = '.env.${environment.name}';
      try {
        await dotenv.load(fileName: envFileName);
      } catch (e) {
        debugPrint('[Main] Failed to load $envFileName: $e');
      }

      // Create and validate configuration
      final config = EnvironmentConfig.fromEnvironment(environment);

      // Initialize logging service (lightweight, no heavy SDKs)
      try {
        await LoggingService.initialize(config);
      } catch (e) {
        debugPrint('[Main] LoggingService init failed: $e');
      }
      LoggingService.info('App starting', {
        'environment': config.environment.name,
        'apiBaseUrl': config.apiBaseUrl,
      });

      // S3-D: forward unknown-enum drift through the same logging service
      // we already configured. `dart:developer.log` stays on as the
      // always-on transport; this gives us a Loki-shipped signal too via
      // LoggingService's pino-side wiring (and Crashlytics if/when wired).
      registerUnknownEnumReporter((enumName, value, fallback) {
        LoggingService.warn('enum_drift', {
          'enum': enumName,
          'value': value,
          'fallback': fallback,
        });
      });

      // Initialize API client
      final apiClient = ApiClient(baseUrl: config.apiBaseUrl);
      try {
        await apiClient.restoreSession();
      } catch (e) {
        LoggingService.warn('Session restore failed, starting fresh', {'error': e.toString()});
      }

      // "Keep me signed in" — when the user has explicitly opted out, we
      // discard the restored session before any UI sees it. This is the
      // security-conscious default so kiosk/shared-device usage is sane.
      final keepSignedIn = await AppPrefsService.getKeepSignedIn();
      if (!keepSignedIn && apiClient.isAuthenticated) {
        try {
          await apiClient.clearTokens();
        } catch (e) {
          LoggingService.warn('Forced sign-out (keep-signed-in=false) failed', {
            'error': e.toString(),
          });
        }
      }

      // Seed the local DB opener with the (possibly restored) user id so
      // every subsequent provider read opens the user's per-account file.
      // SecureStorage is the durable mirror across cold launches.
      final activeUserId = apiClient.currentUserId ??
          await SecureStorageService.getActiveUserId();
      setActiveDatabaseUser(activeUserId);
      if (apiClient.currentUserId != null) {
        await SecureStorageService.setActiveUserId(apiClient.currentUserId);
      }

      LoggingService.info('API client initialized');

      // Initialize Firebase for push notifications and analytics
      // Skip if using placeholder keys (causes native crash in FirebaseInstallations)
      final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
      if (firebaseOptions.apiKey.isEmpty) {
        LoggingService.warn('Firebase skipped — no API key configured in .env', {});
      } else {
        try {
          await Firebase.initializeApp(options: firebaseOptions);
          debugPrint('[Main] Firebase initialized successfully');
        } catch (e) {
          LoggingService.warn('Firebase initialization failed', {'error': e.toString()});
        }
      }

      // --- Global error handlers ---
      // Catch Flutter framework errors (widget build errors, layout errors, etc.)
      FlutterError.onError = (details) {
        LoggingService.error(
          'Flutter framework error',
          details.exception,
          details.stack,
          {'library': details.library ?? 'unknown'},
        );
        // Still show the red error screen in debug mode
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
      };

      // Catch platform errors (native crashes, unhandled async errors)
      PlatformDispatcher.instance.onError = (error, stack) {
        LoggingService.error('Platform error', error, stack);
        return true; // Prevent app termination
      };

      runApp(
        ProviderScope(
          overrides: [
            environmentConfigProvider.overrideWithValue(config),
            apiClientProvider.overrideWith((ref) {
              ref.onDispose(() => apiClient.dispose());
              return apiClient;
            }),
          ],
          child: const AppBootstrap(child: HavenKeepApp()),
        ),
      );
    },
    (error, stack) {
      LoggingService.error('Unhandled zone error', error, stack);
    },
  );
}

/// Global provider for environment configuration.
final environmentConfigProvider = Provider<EnvironmentConfig>((ref) {
  throw UnimplementedError(
    'environmentConfigProvider must be overridden in main()',
  );
});

/// Maximum time the app may sit in the background before we force a
/// biometric re-prompt. Keep tight — the audit calls for >30s.
const _kBiometricLockGracePeriod = Duration(seconds: 30);

/// Root app widget — uses GoRouter and HavenKeep dark theme.
class HavenKeepApp extends ConsumerStatefulWidget {
  const HavenKeepApp({super.key});

  @override
  ConsumerState<HavenKeepApp> createState() => _HavenKeepAppState();
}

class _HavenKeepAppState extends ConsumerState<HavenKeepApp>
    with WidgetsBindingObserver {
  /// Used to push the lock screen from outside the router tree.
  final GlobalKey<NavigatorState> _lockNavKey =
      GlobalKey<NavigatorState>(debugLabel: 'haven-lock-overlay');

  /// Tracks whether the lock screen is currently mounted so we don't
  /// stack multiple instances when the lifecycle bounces.
  bool _lockShown = false;

  /// Wall-clock time the app most recently went into the background. We
  /// only force a re-prompt if it's been longer than the grace period.
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      // Record the moment we left the foreground. Don't overwrite if we
      // already have one — multiple inactive→paused transitions in a row
      // shouldn't reset the timer.
      _backgroundedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _maybeShowLock();
    }
  }

  Future<void> _maybeShowLock() async {
    if (_lockShown) return;

    final enabled = await BiometricService.isBiometricEnabled();
    if (!enabled) {
      _backgroundedAt = null;
      return;
    }

    final lastUnlock = await SecureStorageService.getLastUnlockTimestamp();
    final reference = _backgroundedAt ?? lastUnlock;
    _backgroundedAt = null;

    if (reference != null &&
        DateTime.now().difference(reference) <= _kBiometricLockGracePeriod) {
      return;
    }

    if (!mounted) return;
    final navigator = _lockNavKey.currentState;
    if (navigator == null) return;

    _lockShown = true;
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const BiometricLockScreen(),
      ),
    );
    _lockShown = false;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Initialize offline sync service (listens to connectivity changes)
    ref.watch(offlineSyncServiceProvider);
    // Drive global lifecycle refresh (active warranties on resume).
    ref.watch(appLifecycleServiceProvider);

    return MaterialApp.router(
      title: 'HavenKeep',
      debugShowCheckedModeBanner: false,
      theme: HavenTheme.dark,
      darkTheme: HavenTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppPrefsService.supportedLocales,
      routerConfig: router,
      // Stack a transparent Navigator above the GoRouter tree so we can
      // push the biometric lock screen as a system-modal overlay without
      // fighting GoRouter's redirect rules.
      builder: (context, child) {
        return Navigator(
          key: _lockNavKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// One-time app bootstrap for SDK/service initialization.
class AppBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const AppBootstrap({super.key, required this.child});

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  /// Build-time toggle for demo mode (`--dart-define=DEMO_MODE=true`).
  /// When set, the app skips real auth and bootstraps with the fixture
  /// dataset so screenshots, App Store reviewers, and a local "play
  /// without an account" mode all work without a backend (C201/C202).
  static const _kDemoModeFlag =
      bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  Future<void> _initializeServices() async {
    if (_kDemoModeFlag && !ref.read(demoModeProvider).isEnabled) {
      ref.read(demoModeProvider.notifier).enterDemoMode();
      LoggingService.info('Demo mode auto-enabled via --dart-define', {});
    }

    try {
      await ref.read(premiumServiceProvider).initialize();
    } catch (e) {
      LoggingService.warn('Premium service initialization failed', {'error': e.toString()});
    }

    // Lifecycle observer: refresh active warranties on resumed.
    try {
      ref.read(appLifecycleServiceProvider).start();
    } catch (e) {
      LoggingService.warn(
          'Lifecycle observer init failed', {'error': e.toString()});
    }

    // Deep link handler — havenkeep://gift/<code> + Universal Links.
    try {
      await ref.read(deepLinkServiceProvider).initialize();
    } catch (e) {
      LoggingService.warn('Deep link init failed', {'error': e.toString()});
    }

    // Always initialize the local notification plugin so the Android
    // notification channel ID `havenkeep_default` exists before any FCM
    // payload references it. The FCM service uses this channel post-Phase 7,
    // and Android silently drops notifications for unknown channels.
    try {
      await ref.read(notificationDisplayServiceProvider).initialize();
    } catch (e) {
      LoggingService.warn('Local notification init failed', {
        'error': e.toString(),
      });
    }

    // Only initialize push notifications if Firebase was configured
    if (Firebase.apps.isNotEmpty) {
      try {
        await ref.read(pushNotificationServiceProvider).initialize();
      } catch (e) {
        LoggingService.warn('Push notification initialization failed', {'error': e.toString()});
      }
    } else {
      LoggingService.warn('Push notifications skipped — Firebase not initialized', {});
    }

    // Auto-archive long-expired warranties once per day (authenticated users only).
    if (ref.read(isAuthenticatedProvider)) {
      try {
        final archived =
            await ref.read(autoArchiveServiceProvider).runIfDue();
        if (archived != null && archived > 0) {
          LoggingService.info(
              'Auto-archived $archived expired warranties', {});
        }
      } catch (e) {
        LoggingService.warn('Auto-archive failed', {'error': e.toString()});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
