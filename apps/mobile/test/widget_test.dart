// Basic Flutter widget smoke test.
//
// Verifies the app widget tree builds without error when all required
// providers are overridden (as they would be in main()).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mockito/mockito.dart';
import 'package:api_client/api_client.dart';

import 'package:havenkeep_mobile/main.dart';
import 'package:havenkeep_mobile/core/config/environment.dart';
import 'package:havenkeep_mobile/core/config/environment_config.dart';
import 'package:havenkeep_mobile/core/services/offline_sync_service.dart';

/// Minimal mock so the widget tree can build without a real database.
class _MockOfflineSyncService extends Mock implements OfflineSyncService {
  @override
  bool get isSyncing => false;
}

void main() {
  testWidgets('App smoke test - widget builds without error',
      (WidgetTester tester) async {
    // Load minimal env vars for EnvironmentConfig
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:3000\n');
    final config = EnvironmentConfig.fromEnvironment(Environment.development);
    final apiClient = ApiClient(baseUrl: 'http://localhost:3000');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider.overrideWithValue(config),
          apiClientProvider.overrideWith((ref) {
            ref.onDispose(() => apiClient.dispose());
            return apiClient;
          }),
          // Avoid creating a real sqlite database in tests.
          offlineSyncServiceProvider
              .overrideWithValue(_MockOfflineSyncService()),
        ],
        child: const HavenKeepApp(),
      ),
    );

    // Verify the app renders (MaterialApp.router shows a title).
    expect(find.byType(HavenKeepApp), findsOneWidget);
  });
}
