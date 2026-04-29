import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';
import '../services/maintenance_repository.dart';
import 'auth_provider.dart';
import 'homes_provider.dart';

/// Provides the maintenance repository instance.
final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository(ref.read(apiClientProvider));
});

/// Due/overdue maintenance summary scoped to the active home (2.13).
/// Watching `currentHomeProvider` re-fetches when the user switches homes.
final maintenanceDueProvider = FutureProvider<MaintenanceDueSummary>((ref) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) {
    return const MaintenanceDueSummary(totalDue: 0, totalOverdue: 0, items: []);
  }

  final currentHome = ref.watch(currentHomeProvider);
  return ref.read(maintenanceRepositoryProvider).getDueTasks(homeId: currentHome?.id);
});

/// Maintenance history scoped to the active home (2.13).
final maintenanceHistoryProvider = FutureProvider<List<MaintenanceHistory>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) return [];

  final currentHome = ref.watch(currentHomeProvider);
  return ref.read(maintenanceRepositoryProvider).getHistory(homeId: currentHome?.id);
});

/// Maintenance history filtered to a specific item.
///
/// Powers the inline "Recent maintenance" card on item_detail and is
/// invalidated alongside [maintenanceHistoryProvider] whenever a new
/// task is logged so the per-item view stays in sync.
final maintenanceHistoryByItemProvider =
    FutureProvider.family<List<MaintenanceHistory>, String>((ref, itemId) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) return [];

  return ref.read(maintenanceRepositoryProvider).getHistory(itemId: itemId);
});

/// Maintenance schedules for a specific category.
final maintenanceSchedulesProvider =
    FutureProvider.family<List<MaintenanceSchedule>, String>((ref, category) async {
  return ref.read(maintenanceRepositoryProvider).getSchedules(category);
});
