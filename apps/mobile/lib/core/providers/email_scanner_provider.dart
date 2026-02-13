import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import '../services/email_scanner_repository.dart';
import '../services/email_oauth_service.dart';
import 'auth_provider.dart';

final emailScannerRepositoryProvider = Provider<EmailScannerRepository>((ref) {
  return EmailScannerRepository(ref.read(apiClientProvider));
});

final emailScansProvider =
    AsyncNotifierProvider<EmailScansNotifier, List<EmailScan>>(
  () => EmailScansNotifier(),
);

class EmailScansNotifier extends AsyncNotifier<List<EmailScan>> {
  @override
  Future<List<EmailScan>> build() async {
    final userAsync = ref.watch(currentUserProvider);
    if (userAsync.valueOrNull == null) return [];
    return ref.read(emailScannerRepositoryProvider).getScans();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(
      await ref.read(emailScannerRepositoryProvider).getScans(),
    );
  }

  Future<EmailScan> startScan({
    required String provider,
    required String accessToken,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
  }) async {
    final scan = await ref.read(emailScannerRepositoryProvider).initiateScan(
          provider: provider,
          accessToken: accessToken,
          dateRangeStart: dateRangeStart,
          dateRangeEnd: dateRangeEnd,
        );

    final current = state.value ?? [];
    state = AsyncValue.data([scan, ...current]);
    return scan;
  }

  Future<String> getAccessToken(String provider) async {
    final oauth = ref.read(emailOAuthServiceProvider);
    switch (provider) {
      case 'gmail':
        return oauth.getGmailAccessToken();
      case 'outlook':
        return oauth.getOutlookAccessToken();
      default:
        throw StateError('Unsupported provider: $provider');
    }
  }
}
