import 'dart:async';
import 'dart:collection';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

      // Determine environment from build flavor (defaults to development).
      // The FLAVOR define still drives the in-app `Environment` enum so
      // logging / theming / Crashlytics gates know which env they're in.
      const flavorString = String.fromEnvironment('FLAVOR', defaultValue: 'development');
      final environment = Environment.fromString(flavorString);

      // C15 (audit): we now load a single .env.bundled file rather than
      // .env.${environment.name}. scripts/prepare-env.sh copies the
      // active flavor's file into .env.bundled BEFORE `flutter build`,
      // and pubspec.yaml ships only the bundled file in the IPA/APK
      // assets. Loading from a per-flavor path with all three files
      // bundled would have re-introduced the leak.
      try {
        await dotenv.load(fileName: '.env.bundled');
      } catch (e) {
        debugPrint('[Main] Failed to load .env.bundled: $e');
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

      // S3-D / 2.11: forward unknown-enum drift through LoggingService AND
      // Crashlytics breadcrumbs (when wired). The breadcrumb survives a
      // subsequent crash and gives us "we shipped a server change that
      // produced an enum the client didn't know about, then it crashed
      // five seconds later."
      //
      // H55: buffer events that fire BEFORE Firebase init resolves so
      // the breadcrumb isn't dropped. Drift can happen during the
      // restoreSession parse step (a User row carries an enum value
      // the binary doesn't know yet); without the buffer that event
      // arrived ~50ms before `_crashlyticsReady` flipped and was lost.
      // Once _crashlyticsReady=true the buffer is flushed and future
      // events skip the buffer.
      registerUnknownEnumReporter((enumName, value, fallback) {
        LoggingService.warn('enum_drift', {
          'enum': enumName,
          'value': value,
          'fallback': fallback,
        });
        if (_crashlyticsReady) {
          FirebaseCrashlytics.instance
              .log('enum_drift: $enumName=$value (fallback=$fallback)');
        } else {
          _enumDriftBuffer.add('enum_drift: $enumName=$value (fallback=$fallback)');
          // Bound the buffer so a pathological hot-path doesn't OOM us
          // before Firebase comes up. 256 entries is still trivially
          // small in memory; older drift gets dropped with a single
          // breadcrumb so on-call sees the truncation happened.
          if (_enumDriftBuffer.length > 256) {
            _enumDriftBuffer.removeFirst();
            // Mark that we've started dropping events. The flag is checked
            // at flush time so we emit one "buffer_overflow" event
            // regardless of how many entries fell off.
            _enumDriftBufferOverflowed = true;
          }
        }
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
      //
      // H54: clear the SecureStorage `active_user_id` mirror BEFORE
      // we clear the tokens. The previous order left a stale
      // active_user_id behind, and the DB opener two blocks below
      // read it and opened the just-signed-out user's per-account
      // SQLCipher file. Order matters: kill the mirror first, then
      // the tokens.
      final keepSignedIn = await AppPrefsService.getKeepSignedIn();
      if (!keepSignedIn && apiClient.isAuthenticated) {
        try {
          await SecureStorageService.setActiveUserId(null);
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

      // 4.14 / M-MED-07: warm the persisted theme + locale cache before
      // the first widget builds so cold-start paints the user's chosen
      // values, not the defaults.
      try {
        await AppPrefsService.prewarm();
      } catch (e) {
        LoggingService.warn('Prefs prewarm failed', {'error': e.toString()});
      }

      LoggingService.info('API client initialized');

      // Initialize Firebase for push notifications, Crashlytics, and analytics.
      // Skip if using placeholder keys (causes native crash in FirebaseInstallations).
      final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
      if (firebaseOptions.apiKey.isEmpty) {
        LoggingService.warn('Firebase skipped — no API key configured in .env', {});
      } else {
        try {
          await Firebase.initializeApp(options: firebaseOptions);
          debugPrint('[Main] Firebase initialized successfully');
          // 2.11: enable Crashlytics only in release builds. Debug crashes
          // are noisy + already shown in the IDE. The flag is persisted by
          // the SDK so a single setCollectionEnabled call sticks.
          await FirebaseCrashlytics.instance
              .setCrashlyticsCollectionEnabled(!kDebugMode);
          _crashlyticsReady = true;
          // H55: flush the pre-init enum-drift buffer. Crashlytics now
          // has the breadcrumbs that fired during the ~50-200ms window
          // before _crashlyticsReady flipped. If the buffer overflowed
          // during that window, emit one explicit signal so on-call
          // knows some drift was silently dropped.
          if (_enumDriftBufferOverflowed) {
            FirebaseCrashlytics.instance.log(
              'enum_drift_buffer_overflow: dropped events before Crashlytics was ready',
            );
          }
          while (_enumDriftBuffer.isNotEmpty) {
            FirebaseCrashlytics.instance.log(_enumDriftBuffer.removeFirst());
          }
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
        // 2.11: forward fatal framework errors to Crashlytics. The SDK
        // attaches the active Zone + breadcrumbs to the report. In debug
        // we still call `presentError` so the red screen shows.
        if (_crashlyticsReady) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        }
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
      };

      // Catch platform errors (native crashes, unhandled async errors)
      PlatformDispatcher.instance.onError = (error, stack) {
        LoggingService.error('Platform error', error, stack);
        if (_crashlyticsReady) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        }
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
      // 2.11: catch-all for anything that escapes the Flutter / Platform
      // hooks above. Marked non-fatal so the report shows up in the
      // "non-fatals" pane and doesn't roll up into the crash-free metric
      // (the framework hook already handled the genuine crash).
      if (_crashlyticsReady) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      }
    },
  );
}

/// 2.11: set after FirebaseCrashlytics has been initialised. Guards every
/// call site so the app still works on a developer build with no Firebase
/// API key configured (else the SDK throws on first call).
bool _crashlyticsReady = false;

/// Set true if `_enumDriftBuffer` overflowed before Crashlytics was ready.
/// Surfaced at flush time so on-call knows we dropped breadcrumbs.
bool _enumDriftBufferOverflowed = false;

/// H55: ring buffer for enum-drift breadcrumbs that fire before the
/// Crashlytics SDK is ready. Bounded to 256 entries so a pathological
/// hot-path can't OOM us during boot. Flushed once when
/// `_crashlyticsReady` flips true.
final _enumDriftBuffer = ListQueue<String>();

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
    // `enterDemoMode()` writes a provider synchronously; doing it inside
    // initState would mutate `ProviderScope` mid-build (`!_dirty`). Defer
    // it — and the rest of bootstrap — to after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_kDemoModeFlag && !ref.read(demoModeProvider).isEnabled) {
        ref.read(demoModeProvider.notifier).enterDemoMode();
        LoggingService.info('Demo mode auto-enabled via --dart-define', {});
      }
      _initializeServices();
    });
  }

  /// Build-time toggle for demo mode (`--dart-define=DEMO_MODE=true`).
  /// When set, the app skips real auth and bootstraps with the fixture
  /// dataset so screenshots, App Store reviewers, and a local "play
  /// without an account" mode all work without a backend (C201/C202).
  static const _kDemoModeFlag =
      bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  Future<void> _initializeServices() async {
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
