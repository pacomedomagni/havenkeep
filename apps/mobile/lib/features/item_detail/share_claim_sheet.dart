import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pdf_preview_screen.dart';

/// A bottom sheet that displays warranty claim information and allows the
/// user to copy it to the clipboard.
class ShareClaimSheet extends StatelessWidget {
  final Item item;

  const ShareClaimSheet({super.key, required this.item});

  /// Convenience method to present the sheet.
  static void show(BuildContext context, Item item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: HavenColors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HavenRadius.card),
        ),
      ),
      builder: (_) => ShareClaimSheet(item: item),
    );
  }

  String _formatDate(DateTime date) => DateFormat.yMMMd().format(date);

  String _buildClaimText() {
    final buffer = StringBuffer();
    buffer.writeln('Warranty Claim Information');
    buffer.writeln('-------------------------');
    buffer.writeln(
      '${item.brand != null ? '${item.brand} ' : ''}${item.name}',
    );
    buffer.writeln(
      'Model: ${item.modelNumber ?? '\u2014'}',
    );
    buffer.writeln(
      'Serial: ${item.serialNumber ?? '\u2014'}',
    );
    buffer.writeln('Purchased: ${_formatDate(item.purchaseDate)}');
    if (item.warrantyEndDate != null) {
      buffer.writeln(
        'Warranty expires: ${_formatDate(item.warrantyEndDate!)}',
      );
    }
    buffer.writeln('Store: ${item.store ?? '\u2014'}');
    buffer.writeln(
      'Price: ${item.price != null ? '\$${item.price!.toStringAsFixed(2)}' : '\u2014'}',
    );
    buffer.writeln(
      'Provider: ${item.warrantyProvider ?? '\u2014'}',
    );
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HavenSpacing.lg,
          HavenSpacing.sm,
          HavenSpacing.lg,
          HavenSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: HavenColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: HavenSpacing.md),

            // Title
            Text(
              'Share Claim Info',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: HavenSpacing.md),

            // Info card
            Container(
              padding: const EdgeInsets.all(HavenSpacing.md),
              decoration: BoxDecoration(
                color: HavenColors.surface,
                border: Border.all(color: HavenColors.border),
                borderRadius: BorderRadius.circular(HavenRadius.button),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  Text(
                    [if (item.brand != null) item.brand!, item.name].join(' '),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  _InfoLine('Model', item.modelNumber),
                  _InfoLine('Serial', item.serialNumber),
                  _InfoLine('Purchased', _formatDate(item.purchaseDate)),
                  _InfoLine(
                    'Warranty expires',
                    item.warrantyEndDate != null
                        ? _formatDate(item.warrantyEndDate!)
                        : null,
                  ),
                  _InfoLine('Store', item.store),
                  _InfoLine(
                    'Price',
                    item.price != null
                        ? '\$${item.price!.toStringAsFixed(2)}'
                        : null,
                  ),
                  _InfoLine('Provider', item.warrantyProvider),
                ],
              ),
            ),
            const SizedBox(height: HavenSpacing.md),

            // Copy to clipboard
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _buildClaimText()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy to Clipboard'),
              ),
            ),
            const SizedBox(height: HavenSpacing.sm),

            // Email
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final claimText = _buildClaimText();
                  final productName =
                      [if (item.brand != null) item.brand!, item.name]
                          .join(' ');
                  final subject =
                      Uri.encodeComponent('Warranty Claim: $productName');
                  final body = Uri.encodeComponent(claimText);
                  final uri = Uri.parse('mailto:?subject=$subject&body=$body');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.email_outlined, size: 18),
                label: const Text('Email'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.secondary,
                  side: const BorderSide(color: HavenColors.border),
                  padding: const EdgeInsets.symmetric(
                    vertical: HavenSpacing.sm + 4,
                    horizontal: HavenSpacing.md,
                  ),
                ),
              ),
            ),
            const SizedBox(height: HavenSpacing.sm),

            // Text Message
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final claimText = _buildClaimText();
                  final body = Uri.encodeComponent(claimText);
                  final uri = Uri.parse('sms:?body=$body');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.message_outlined, size: 18),
                label: const Text('Text Message'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.secondary,
                  side: const BorderSide(color: HavenColors.border),
                  padding: const EdgeInsets.symmetric(
                    vertical: HavenSpacing.sm + 4,
                    horizontal: HavenSpacing.md,
                  ),
                ),
              ),
            ),
            const SizedBox(height: HavenSpacing.sm),

            // Save as PDF
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfPreviewScreen(item: item),
                      fullscreenDialog: true,
                    ),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Save as PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.secondary,
                  side: const BorderSide(color: HavenColors.border),
                  padding: const EdgeInsets.symmetric(
                    vertical: HavenSpacing.sm + 4,
                    horizontal: HavenSpacing.md,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info line within the card
// ---------------------------------------------------------------------------

class _InfoLine extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.xs),
      child: Text(
        '$label: ${value ?? '\u2014'}',
        style: const TextStyle(
          fontSize: 14,
          color: HavenColors.textSecondary,
        ),
      ),
    );
  }
}

