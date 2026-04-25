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

    // While auth is still resolving, suspend on a never-completing future
    // so this provider stays in `AsyncLoading` (instead of synthesizing
    // an `AsyncData([])` that downstream guards would mistake for "no
    // homes"). The router and any UI consumer must observe loading and
    // wait — see C101 in the audit.
    if (userAsync.isLoading) {
      return Completer<List<Home>>().future;
    }

    final user = userAsync.valueOrNull;
    if (user == null) {
      _previousUserId = null;
      return [];
    }

    // Detect account switches — if the active user changed, drop any
    // cached homes so we never serve user A's data while user B's fetch
    // is in flight.
    if (_previousUserId != null && _previousUserId != user.id) {
      state = const AsyncValue.loading();
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
///
/// Wrapped in `AsyncValue` so callers can distinguish "still loading"
/// from "definitely (no) homes". The router uses this to keep
/// authenticated users on the splash screen until the answer is real
/// instead of redirecting on a speculative value (C101).
final hasHomeProvider = Provider<AsyncValue<bool>>((ref) {
  final homes = ref.watch(homesProvider);
  return homes.whenData((list) => list.isNotEmpty);
});
