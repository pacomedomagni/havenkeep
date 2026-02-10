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
}
