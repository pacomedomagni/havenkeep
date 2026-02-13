import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_models/shared_models.dart';

/// Generates and shares CSV exports of items.
class CsvExportService {
  static final _dateFormat = DateFormat('yyyy-MM-dd');

  /// Export a list of items to CSV and open the share sheet.
  Future<void> exportItemsToCsv(List<Item> items) async {
    final headers = [
      'Name',
      'Brand',
      'Category',
      'Room',
      'Model Number',
      'Serial Number',
      'Purchase Date',
      'Store',
      'Price',
      'Warranty Type',
      'Warranty Months',
      'Warranty End Date',
      'Status',
      'Notes',
    ];

    final rows = <List<String>>[headers];

    for (final item in items) {
      rows.add([
        item.name,
        item.brand ?? '',
        item.category.displayLabel,
        item.room?.displayLabel ?? '',
        item.modelNumber ?? '',
        item.serialNumber ?? '',
        _dateFormat.format(item.purchaseDate),
        item.store ?? '',
        item.price != null ? item.price!.toStringAsFixed(2) : '',
        item.warrantyType.displayLabel,
        item.warrantyMonths.toString(),
        item.warrantyEndDate != null
            ? _dateFormat.format(item.warrantyEndDate!)
            : '',
        item.computedWarrantyStatus.displayLabel,
        item.notes ?? '',
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);

    final dir = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd').format(DateTime.now());
    final file = File('${dir.path}/havenkeep_items_$timestamp.csv');
    await file.writeAsString(csvData);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'HavenKeep Items Export',
      ),
    );
  }
}

/// Riverpod provider for the CSV export service.
final csvExportServiceProvider = Provider<CsvExportService>((ref) {
  return CsvExportService();
});
