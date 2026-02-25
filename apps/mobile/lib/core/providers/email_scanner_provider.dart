import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import '../services/email_scanner_repository.dart';
import '../services/email_oauth_service.dart';
import 'auth_provider.dart';
import 'items_provider.dart';

final emailScannerRepositoryProvider = Provider<EmailScannerRepository>((ref) {
  return EmailScannerRepository(ref.read(apiClientProvider));
});

final emailScansProvider =
    AsyncNotifierProvider<EmailScansNotifier, List<EmailScan>>(
  () => EmailScansNotifier(),
);

class EmailScansNotifier extends AsyncNotifier<List<EmailScan>> {
  final Map<String, Timer> _pollingTimers = {};
  static const _pollInterval = Duration(seconds: 4);
  static const _pollTimeout = Duration(minutes: 6);

  @override
  Future<List<EmailScan>> build() async {
    final userAsync = ref.watch(currentUserProvider);
    if (userAsync.valueOrNull == null) return [];
    final scans = await ref.read(emailScannerRepositoryProvider).getScans();
    // Resume polling for any scans still in progress
    for (final scan in scans) {
      if (scan.status == EmailScanStatus.scanning) {
        _startPolling(scan.id);
      }
    }
    return scans;
  }

  @override
  void dispose() {
    for (final timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return ref.read(emailScannerRepositoryProvider).getScans();
    });
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

    // Start polling to track scan progress
    _startPolling(scan.id);

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

  void _startPolling(String scanId) {
    // Don't double-poll
    if (_pollingTimers.containsKey(scanId)) return;

    final deadline = DateTime.now().add(_pollTimeout);

    final timer = Timer.periodic(_pollInterval, (t) async {
      // Stop if past timeout
      if (DateTime.now().isAfter(deadline)) {
        t.cancel();
        _pollingTimers.remove(scanId);
        return;
      }

      try {
        final updated =
            await ref.read(emailScannerRepositoryProvider).getScanById(scanId);
        _updateScanInState(updated);

        if (updated.status != EmailScanStatus.scanning) {
          t.cancel();
          _pollingTimers.remove(scanId);

          // Refresh items list if new items were imported
          if (updated.itemsImported > 0) {
            ref.invalidate(itemsProvider);
          }
        }
      } catch (_) {
        // Silently ignore transient poll errors
      }
    });

    _pollingTimers[scanId] = timer;
  }

  void _updateScanInState(EmailScan updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final s in current)
        if (s.id == updated.id) updated else s,
    ]);
  }
}
