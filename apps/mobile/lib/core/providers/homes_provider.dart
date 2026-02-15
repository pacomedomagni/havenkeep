import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';
import '../services/homes_repository.dart';
import 'auth_provider.dart';

/// Provides the homes repository instance.
final homesRepositoryProvider = Provider<HomesRepository>((ref) {
  return HomesRepository(ref.read(apiClientProvider));
});

/// All homes for the current user.
final homesProvider =
    AsyncNotifierProvider<HomesNotifier, List<Home>>(
  () => HomesNotifier(),
);

class HomesNotifier extends AsyncNotifier<List<Home>> {
  /// Track the previous user ID to detect account switches.
  String? _previousUserId;

  @override
  Future<List<Home>> build() async {
    final userAsync = ref.watch(currentUserProvider);

    // If auth is still loading, preserve current state to avoid flashing empty
    // BUT only if the user hasn't changed (prevent stale data across user switches)
    if (userAsync.isLoading) {
      final currentUserId = userAsync.valueOrNull?.id;
      if (_previousUserId != null && currentUserId != null && _previousUserId != currentUserId) {
        // User has changed — return empty list to avoid showing stale homes
        _previousUserId = currentUserId;
        return [];
      }
      final prevHomes = state.valueOrNull ?? [];
      return prevHomes;
    }

    final user = userAsync.valueOrNull;
    if (user == null) {
      _previousUserId = null;
      return [];
    }

    _previousUserId = user.id;
    return ref.read(homesRepositoryProvider).getHomes();
  }

  /// Add a new home.
  Future<Home> addHome(Home home) async {
    final newHome = await ref.read(homesRepositoryProvider).createHome(home);

    final currentHomes = state.value ?? [];
    state = AsyncValue.data([...currentHomes, newHome]);

    return newHome;
  }

  /// Update an existing home.
  Future<Home> updateHome(Home home) async {
    final updated = await ref.read(homesRepositoryProvider).updateHome(home);

    final currentHomes = state.value ?? [];
    state = AsyncValue.data(
      currentHomes.map((h) => h.id == updated.id ? updated : h).toList(),
    );

    return updated;
  }

  /// Delete a home.
  Future<void> deleteHome(String id) async {
    await ref.read(homesRepositoryProvider).deleteHome(id);

    final currentHomes = state.value ?? [];
    state = AsyncValue.data(
      currentHomes.where((h) => h.id != id).toList(),
    );
  }
}

/// Persists the user's selected home ID across sessions.
final selectedHomeIdProvider = StateProvider<String?>((ref) => null);

/// The current/selected home. Uses the user's selection, or defaults to first.
final currentHomeProvider = Provider<Home?>((ref) {
  final homes = ref.watch(homesProvider);
  final selectedId = ref.watch(selectedHomeIdProvider);

  return homes.whenOrNull(
    data: (homesList) {
      if (homesList.isEmpty) return null;
      if (selectedId != null) {
        final match = homesList.where((h) => h.id == selectedId);
        if (match.isNotEmpty) return match.first;
      }
      return homesList.first;
    },
  );
});

/// Whether the user has at least one home set up.
/// Returns true while loading to prevent premature redirect to home setup.
final hasHomeProvider = Provider<bool>((ref) {
  final homes = ref.watch(homesProvider);
  if (homes.isLoading) return true;
  return ref.watch(currentHomeProvider) != null;
});
