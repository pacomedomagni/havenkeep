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
  @override
  Future<List<Home>> build() async {
    ref.watch(currentUserProvider);

    final user = ref.read(currentUserProvider).value;
    if (user == null) return [];

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

/// The current/selected home (defaults to first home).
final currentHomeProvider = Provider<Home?>((ref) {
  final homes = ref.watch(homesProvider);
  return homes.whenOrNull(
    data: (homesList) => homesList.isNotEmpty ? homesList.first : null,
  );
});

/// Whether the user has at least one home set up.
final hasHomeProvider = Provider<bool>((ref) {
  return ref.watch(currentHomeProvider) != null;
});
