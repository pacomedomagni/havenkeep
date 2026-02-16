import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_ui/shared_ui.dart';

import 'core/config/environment.dart';
import 'core/config/environment_config.dart';
import 'core/config/firebase_options.dart';
import 'core/router/router.dart';
import 'core/database/database.dart';
import 'core/services/logging_service.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/providers/premium_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
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
  await dotenv.load(fileName: envFileName);

  // Create and validate configuration
  final config = EnvironmentConfig.fromEnvironment(environment);

  // Initialize logging service (lightweight, no heavy SDKs)
  await LoggingService.initialize(config);
  LoggingService.info('App starting', {
    'environment': config.environment.name,
    'apiBaseUrl': config.apiBaseUrl,
  });

  // Initialize API client
  final apiClient = ApiClient(baseUrl: config.apiBaseUrl);
  setGlobalApiClient(apiClient);
  try {
    await apiClient.restoreSession();
  } catch (e) {
    LoggingService.warn('Session restore failed, starting fresh', {'error': e.toString()});
  }

  LoggingService.info('API client initialized');

  // Initialize Firebase for push notifications and analytics
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[Main] Firebase initialized successfully');
  } catch (e) {
    LoggingService.warn('Firebase initialization failed', {'error': e.toString()});
  }

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
}

/// Global provider for environment configuration.
final environmentConfigProvider = Provider<EnvironmentConfig>((ref) {
  throw UnimplementedError(
    'environmentConfigProvider must be overridden in main()',
  );
});

/// Root app widget — uses GoRouter and HavenKeep dark theme.
class HavenKeepApp extends ConsumerWidget {
  const HavenKeepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Initialize offline sync service (listens to connectivity changes)
    ref.watch(offlineSyncServiceProvider);

    return MaterialApp.router(
      title: 'HavenKeep',
      debugShowCheckedModeBanner: false,
      theme: HavenTheme.dark,
      routerConfig: router,
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
    Future(() async {
      try {
        await ref.read(premiumServiceProvider).initialize();
      } catch (e) {
        LoggingService.warn('Premium service initialization failed', {'error': e.toString()});
      }

      try {
        await ref.read(pushNotificationServiceProvider).initialize();
      } catch (e) {
        LoggingService.warn('Push notification initialization failed', {'error': e.toString()});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
