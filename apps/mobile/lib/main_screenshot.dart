// Dedicated app entry for `scripts/capture-store-screenshots.sh`.
//
// Boots the regular app, programmatically signs in as the dev user,
// then walks a curated list of routes with a delay between each. Prints
// `[SCREENSHOT_READY] <name>` to stdout between routes — the capture
// script tails the log + runs `xcrun simctl io … screenshot` after each
// marker. Final marker is `[SCREENSHOT_DONE]`.
//
// Run as:
//   flutter run -t lib/main_screenshot.dart -d "iPhone 17 Pro Max"
//
// Why a dedicated entrypoint instead of integration_test:
//   integration_test conflicts with the app's `runZonedGuarded` +
//   custom FlutterError.onError + AppBootstrap initialization. This
//   entrypoint is the real Flutter app, so screenshots taken by
//   `simctl io screenshot` capture the genuine rendered surface.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:api_client/api_client.dart';

import 'core/config/environment.dart';
import 'core/config/environment_config.dart';
import 'core/config/firebase_options.dart';
import 'core/database/database.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/homes_provider.dart';
import 'core/providers/items_provider.dart';
import 'core/router/router.dart';
import 'core/services/logging_service.dart';
import 'core/services/secure_storage_service.dart';
import 'main.dart' show HavenKeepApp, AppBootstrap, environmentConfigProvider;

const _devEmail = 'dev@havenkeep.com';
const _devPassword = 'DevPass1234!';

/// Each marker the capture script grep-watches for. The walk runs in
/// order. Item-detail is appended at the end because it needs the
/// items provider to have hydrated.
const List<({String name, String route})> _walk = [
  (name: '01-dashboard', route: '/dashboard'),
  (name: '02-items-list', route: '/items'),
  (name: '04-maintenance', route: '/maintenance'),
  (name: '05-claims-savings', route: '/warranty-claims'),
  (name: '06-email-scanner', route: '/settings/email-scanner'),
  (name: '07-premium', route: '/premium'),
  (name: '08-recent-gifts', route: '/settings/gifts'),
];

void _emit(String marker) {
  // ignore: avoid_print
  print(marker);
}

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);

      const flavorString = String.fromEnvironment('FLAVOR', defaultValue: 'development');
      final environment = Environment.fromString(flavorString);
      try {
        await dotenv.load(fileName: '.env.${environment.name}');
      } catch (e) {
        debugPrint('[Screenshot] dotenv load skipped: $e');
      }

      // The Android emulator's loopback is itself, not the host. Override
      // the dotenv-loaded API_BASE_URL with 10.0.2.2 (QEMU's host bridge
      // alias) so the screenshot driver's API client can reach our local
      // docker stack. iOS simulator shares the host network, so 127.0.0.1
      // there is correct as-is.
      if (Platform.isAndroid) {
        dotenv.env['API_BASE_URL'] = 'http://10.0.2.2:3000';
      }

      final config = EnvironmentConfig.fromEnvironment(environment);

      try {
        await LoggingService.initialize(config);
      } catch (e) {
        debugPrint('[Screenshot] LoggingService init skipped: $e');
      }

      final apiClient = ApiClient(baseUrl: config.apiBaseUrl);
      try {
        await apiClient.restoreSession();
      } catch (_) {/* fine — first launch */}

      // Force sign-out so the captured screens reflect a fresh login
      // by the dev user, not whatever was in the keychain.
      try {
        await apiClient.clearTokens();
      } catch (_) {}

      final activeUserId = apiClient.currentUserId ??
          await SecureStorageService.getActiveUserId();
      setActiveDatabaseUser(activeUserId);

      // Skip Firebase if no API key (matches main.dart's guard).
      final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
      if (firebaseOptions.apiKey.isNotEmpty) {
        try {
          await Firebase.initializeApp(options: firebaseOptions);
        } catch (_) {/* non-fatal */}
      }

      // Skip the first-launch intro carousel for the capture run.
      // Biometric lock is opt-in via AppPrefsService.setBiometricLockEnabled
      // and isn't enabled by default — no override needed for the dev user.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_intro_seen', true);

      runApp(
        ProviderScope(
          overrides: [
            environmentConfigProvider.overrideWithValue(config),
            apiClientProvider.overrideWith((ref) {
              ref.onDispose(() => apiClient.dispose());
              return apiClient;
            }),
          ],
          child: const _ScreenshotDriverGate(
            child: AppBootstrap(child: HavenKeepApp()),
          ),
        ),
      );
    },
    (error, stack) {
      // ignore: avoid_print
      print('[SCREENSHOT_PHASE] zone error: $error');
    },
  );
}

class _ScreenshotDriverGate extends ConsumerStatefulWidget {
  final Widget child;
  const _ScreenshotDriverGate({required this.child});

  @override
  ConsumerState<_ScreenshotDriverGate> createState() =>
      _ScreenshotDriverGateState();
}

class _ScreenshotDriverGateState extends ConsumerState<_ScreenshotDriverGate> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runWalk());
  }

  Future<void> _runWalk() async {
    if (_started) return;
    _started = true;

    // Warm up so the splash screen + router can mount + animate to
    // welcome before we start signing in.
    await Future<void>.delayed(const Duration(seconds: 3));

    _emit('[SCREENSHOT_PHASE] sign-in');
    try {
      final user = await ref
          .read(currentUserProvider.notifier)
          .signInWithEmail(email: _devEmail, password: _devPassword);
      _emit('[SCREENSHOT_PHASE] signed in as ${user?.email}');
    } catch (e) {
      _emit('[SCREENSHOT_PHASE] sign-in failed: $e');
      _emit('[SCREENSHOT_DONE]');
      return;
    }

    // Force the homes provider to fetch first — itemsProvider filters by
    // currentHomeProvider which needs homes data, otherwise the
    // dashboard + items list render their empty states.
    try {
      final homes = await ref.read(homesProvider.future);
      _emit('[SCREENSHOT_PHASE] homes loaded: ${homes.length}');
      // Pin the first home as the current one so currentHomeProvider
      // resolves to a real value before any screen reads it.
      if (homes.isNotEmpty) {
        ref.read(selectedHomeIdProvider.notifier).state = homes.first.id;
      }
    } catch (e) {
      _emit('[SCREENSHOT_PHASE] homes fetch failed: $e');
    }

    // Force the items provider to fetch. .future awaits the underlying
    // AsyncValue, returning the resolved list.
    List items = const [];
    try {
      items = await ref.read(itemsProvider.future);
    } catch (e) {
      _emit('[SCREENSHOT_PHASE] items fetch failed: $e');
    }
    _emit('[SCREENSHOT_PHASE] items loaded: ${items.length}');

    // Offline sync starts a "Syncing…" badge in the dashboard header
    // immediately after auth. Wait it out before the first capture so
    // the production screenshot doesn't show a transient indicator.
    await Future<void>.delayed(const Duration(seconds: 5));

    final router = ref.read(routerProvider);

    for (final step in _walk) {
      router.go(step.route);
      // Generous settle window — first navigation to a route triggers
      // its providers' first fetch; we want lists populated before the
      // shell snaps the screenshot.
      await Future<void>.delayed(const Duration(milliseconds: 2800));
      _emit('[SCREENSHOT_READY] ${step.name}');
      // Give the shell capture loop time to take the screenshot.
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    // Item detail — runs last because we need the items provider's data.
    final fridge = items
        .where((i) => i.name.contains('Refrigerator'))
        .toList();
    if (fridge.isNotEmpty) {
      router.go('/items/${fridge.first.id}');
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      _emit('[SCREENSHOT_READY] 03-item-detail');
      await Future<void>.delayed(const Duration(milliseconds: 900));
    } else {
      _emit('[SCREENSHOT_PHASE] no Refrigerator in items — skipping detail');
    }

    _emit('[SCREENSHOT_DONE]');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
