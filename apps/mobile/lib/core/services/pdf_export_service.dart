import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_models/shared_models.dart';

/// Generates and shares PDF warranty claim documents.
class PdfExportService {
  /// Brand color for the PDF header.
  static final _brandColor = PdfColor.fromHex('#6C63FF');
  static final _darkBg = PdfColor.fromHex('#121212');
  static final _cardBg = PdfColor.fromHex('#1E1E1E');
  static final _textPrimary = PdfColor.fromHex('#FFFFFF');
  static final _textSecondary = PdfColor.fromHex('#B0B0B0');
  static final _borderColor = PdfColor.fromHex('#2A2A2A');

  /// Generate a PDF warranty claim document for an item.
  Future<Uint8List> generateWarrantyClaimPdf(
    Item item, {
    List<Document>? documents,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.interRegular(),
        bold: await PdfGoogleFonts.interBold(),
      ),
    );

    final dateFormat = DateFormat.yMMMd();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: _brandColor,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'HavenKeep',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Warranty Claim Document',
                      style: pw.TextStyle(
                        color: PdfColors.white.shade(200),
                        fontSize: 14,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Generated on ${dateFormat.format(DateTime.now())}',
                      style: pw.TextStyle(
                        color: PdfColors.white.shade(200),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Product Information
              _buildSection('Product Information', [
                _buildRow('Product', '${item.brand ?? ''} ${item.name}'.trim()),
                _buildRow('Category', item.category.displayLabel),
                _buildRow('Model Number', item.modelNumber ?? '\u2014'),
                _buildRow('Serial Number', item.serialNumber ?? '\u2014'),
                if (item.barcode != null)
                  _buildRow('Barcode', item.barcode!),
                if (item.room != null)
                  _buildRow('Location', item.room!.displayLabel),
              ]),
              pw.SizedBox(height: 16),

              // Warranty Information
              _buildSection('Warranty Information', [
                _buildRow('Warranty Type', item.warrantyType.displayLabel),
                _buildRow('Duration', '${item.warrantyMonths} months'),
                _buildRow(
                  'Warranty Expires',
                  item.warrantyEndDate != null
                      ? dateFormat.format(item.warrantyEndDate!)
                      : '\u2014',
                ),
                _buildRow('Status', item.computedWarrantyStatus.displayLabel),
                _buildRow(
                  'Days Remaining',
                  '${item.computedDaysRemaining}',
                ),
                if (item.warrantyProvider != null)
                  _buildRow('Provider', item.warrantyProvider!),
              ]),
              pw.SizedBox(height: 16),

              // Purchase Information
              _buildSection('Purchase Information', [
                _buildRow('Purchase Date', dateFormat.format(item.purchaseDate)),
                _buildRow('Store', item.store ?? '\u2014'),
                _buildRow(
                  'Price',
                  item.price != null
                      ? '\$${item.price!.toStringAsFixed(2)}'
                      : '\u2014',
                ),
              ]),

              // Notes
              if (item.notes != null && item.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                _buildSection('Notes', [
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _borderColor),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      item.notes!,
                      style: pw.TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ]),
              ],

              // Documents summary
              if (documents != null && documents.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                _buildSection('Attached Documents', [
                  ...documents.map(
                    (doc) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 4,
                            height: 4,
                            decoration: pw.BoxDecoration(
                              color: _textSecondary,
                              shape: pw.BoxShape.circle,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            '${doc.fileName} (${doc.type.displayLabel})',
                            style: pw.TextStyle(
                              color: _textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ],

              pw.Spacer(),

              // Footer
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.only(top: 12),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: _borderColor),
                  ),
                ),
                child: pw.Text(
                  'Generated by HavenKeep — Your Warranties. Protected.',
                  style: pw.TextStyle(
                    color: _textSecondary,
                    fontSize: 9,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Share a PDF via the system share sheet.
  Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// Print the PDF directly.
  Future<void> printPdf(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  // ---- Helpers ----

  pw.Widget _buildSection(String title, List<pw.Widget> children) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _brandColor,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 8),
        ...children,
      ],
    );
  }

  pw.Widget _buildRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                color: _textSecondary,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Riverpod provider for the PDF export service.
final pdfExportServiceProvider = Provider<PdfExportService>((ref) {
  return PdfExportService();
});
