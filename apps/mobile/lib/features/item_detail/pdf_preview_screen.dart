import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/documents_provider.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/utils/error_handler.dart';

/// Full-screen PDF preview of a warranty claim document.
///
/// Shows a live preview of the generated PDF with options to
/// share or print the document.
class PdfPreviewScreen extends ConsumerStatefulWidget {
  final Item item;

  const PdfPreviewScreen({super.key, required this.item});

  @override
  ConsumerState<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends ConsumerState<PdfPreviewScreen> {
  Uint8List? _pdfBytes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    try {
      final service = ref.read(pdfExportServiceProvider);
      final docs = ref.read(documentsForItemProvider(widget.item.id)).value;

      final bytes = await service.generateWarrantyClaimPdf(
        widget.item,
        documents: docs,
      );

      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorHandler.getUserMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _share() async {
    if (_pdfBytes == null) return;

    final productName =
        '${widget.item.brand ?? ''} ${widget.item.name}'.trim();
    final filename = 'HavenKeep_Claim_${productName.replaceAll(' ', '_')}.pdf';

    await ref.read(pdfExportServiceProvider).sharePdf(_pdfBytes!, filename);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text(
          'Warranty Claim',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_pdfBytes != null) ...[
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Print',
              onPressed: () async {
                await ref
                    .read(pdfExportServiceProvider)
                    .printPdf(_pdfBytes!);
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _share,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: HavenColors.primary),
            SizedBox(height: HavenSpacing.md),
            Text(
              'Generating PDF...',
              style: TextStyle(
                color: HavenColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: HavenColors.expired,
              ),
              const SizedBox(height: HavenSpacing.md),
              const Text(
                'Failed to generate PDF',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),
              const SizedBox(height: HavenSpacing.sm),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: HavenColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HavenSpacing.lg),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _generatePdf();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Show PDF preview
    return PdfPreview(
      build: (_) => _pdfBytes!,
      canChangePageFormat: false,
      canDebug: false,
      pdfFileName:
          'HavenKeep_Claim_${widget.item.name.replaceAll(' ', '_')}.pdf',
      actions: const [],  // We use our own AppBar actions
    );
  }
}
