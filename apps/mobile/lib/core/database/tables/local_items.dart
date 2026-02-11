import 'package:drift/drift.dart';

/// Drift table mirroring the `items` table for offline storage.
class LocalItems extends Table {
  TextColumn get id => text()();
  TextColumn get homeId => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get modelNumber => text().nullable()();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('other'))();
  TextColumn get room => text().nullable()();
  TextColumn get productImageUrl => text().nullable()();
  TextColumn get barcode => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime()();
  TextColumn get store => text().nullable()();
  RealColumn get price => real().nullable()();
  IntColumn get warrantyMonths => integer().withDefault(const Constant(12))();
  DateTimeColumn get warrantyEndDate => dateTime().nullable()();
  TextColumn get warrantyType => text().withDefault(const Constant('manufacturer'))();
  TextColumn get warrantyProvider => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  TextColumn get addedVia => text().withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
