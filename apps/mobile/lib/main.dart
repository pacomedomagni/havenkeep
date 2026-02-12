import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_ui/shared_ui.dart';

import 'core/config/environment.dart';
import 'core/config/environment_config.dart';
import 'core/router/router.dart';
import 'core/database/database.dart';
import 'core/services/logging_service.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/push_notification_service.dart';

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
  await apiClient.restoreSession();

  LoggingService.info('API client initialized');

  // Initialize Firebase (guarded — stub config may not be valid)
  // TODO: Enable Firebase after completing Phase 1.3
  try {
    // Uncomment when Firebase project is configured:
    // await Firebase.initializeApp(
    //   options: DefaultFirebaseOptions.currentPlatform,
    // );
    debugPrint('[Main] Firebase init skipped (stub config)');
  } catch (e) {
    debugPrint('[Main] Firebase init failed (expected with stub): $e');
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
      child: const HavenKeepApp(),
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
