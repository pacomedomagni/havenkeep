import 'package:drift/drift.dart';

/// Drift table mirroring the Supabase `homes` table for offline storage.
class LocalHomes extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get state => text().nullable()();
  TextColumn get zip => text().nullable()();
  TextColumn get homeType => text().withDefault(const Constant('house'))();
  DateTimeColumn get moveInDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
