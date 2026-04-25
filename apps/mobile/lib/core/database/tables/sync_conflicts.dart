import 'package:drift/drift.dart';

/// Parked sync conflicts surfaced for the user to resolve manually.
///
/// When the offline sync service hits a 409 it can no longer auto-merge,
/// it writes the local + server JSON snapshots here so the UI can present
/// a side-by-side resolution flow.
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get localVersionJson => text()();
  TextColumn get serverVersionJson => text()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
