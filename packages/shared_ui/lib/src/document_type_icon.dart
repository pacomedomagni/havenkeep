import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// Helper to get an appropriate Material icon for each document type.
class DocumentTypeIcon {
  DocumentTypeIcon._();

  /// Get the IconData for a [DocumentType].
  static IconData get(DocumentType type) {
    return switch (type) {
      DocumentType.receipt => Icons.receipt_long,
      DocumentType.warranty_card => Icons.verified_user,
      DocumentType.manual => Icons.menu_book,
      DocumentType.invoice => Icons.description,
      DocumentType.other => Icons.attach_file,
    };
  }

  /// Returns an [Icon] widget for the given [DocumentType].
  static Widget widget(
    DocumentType type, {
    double size = 20,
    Color? color,
  }) {
    return Icon(
      get(type),
      size: size,
      color: color,
    );
  }
}
