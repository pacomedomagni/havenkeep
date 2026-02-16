import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';

/// Stream of connectivity state changes.
final connectivityProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Whether the device currently has network connectivity.
final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    data: (results) => results.any((r) => r != ConnectivityResult.none),
    loading: () => true, // Assume online while checking
    error: (_, __) => true, // Assume online on error
  );
});

/// Count of pending offline sync actions.
final offlineQueueCountProvider = FutureProvider<int>((ref) async {
  // Re-evaluate when connectivity changes
  ref.watch(connectivityProvider);
  try {
    return await ref.read(localDatabaseProvider).pendingCount;
  } catch (e) {
    return 0;
  }
});
