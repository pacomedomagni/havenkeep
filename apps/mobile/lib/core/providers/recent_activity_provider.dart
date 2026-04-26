import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audit_log_repository.dart';
import 'auth_provider.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository(ref.read(apiClientProvider));
});

/// Last-N items from the user's audit log, surfaced as the dashboard
/// "Recent activity" feed. Skips the network when the user isn't signed in
/// so the dashboard's other AsyncProviders don't see a 401 cascade.
final recentActivityProvider =
    FutureProvider<List<RecentActivity>>((ref) async {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const [];
  return ref.read(auditLogRepositoryProvider).getRecentActivity(limit: 10);
});
