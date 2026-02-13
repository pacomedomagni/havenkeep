import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';
import '../services/maintenance_repository.dart';
import 'auth_provider.dart';

/// Provides the maintenance repository instance.
final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository(ref.read(apiClientProvider));
});

/// Due/overdue maintenance summary across all items.
final maintenanceDueProvider = FutureProvider<MaintenanceDueSummary>((ref) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) {
    return const MaintenanceDueSummary(totalDue: 0, totalOverdue: 0, items: []);
  }

  return ref.read(maintenanceRepositoryProvider).getDueTasks();
});

/// Maintenance history for the current user.
final maintenanceHistoryProvider = FutureProvider<List<MaintenanceHistory>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) return [];

  return ref.read(maintenanceRepositoryProvider).getHistory();
});

/// Maintenance schedules for a specific category.
final maintenanceSchedulesProvider =
    FutureProvider.family<List<MaintenanceSchedule>, String>((ref, category) async {
  return ref.read(maintenanceRepositoryProvider).getSchedules(category);
});
