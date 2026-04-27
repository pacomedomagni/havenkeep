import 'package:drift/drift.dart';

/// Offline action queue — stores pending changes to sync when online.
class OfflineQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'item', 'home', 'document', 'preferences'
  TextColumn get entityId => text()();
  TextColumn get action => text()(); // OfflineAction enum value
  TextColumn get payload => text()(); // JSON-encoded payload
  TextColumn get status => text().withDefault(const Constant('pending'))(); // OfflineStatus enum value
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  // S2-E / S2-C: caller-supplied UUID generated at enqueue time. Threaded
  // through every API call this entry ever produces (initial send +
  // retries) so the server's idempotency middleware can collapse a
  // re-sent in-flight entry back to the original write.
  TextColumn get idempotencyKey => text().nullable()();
}
