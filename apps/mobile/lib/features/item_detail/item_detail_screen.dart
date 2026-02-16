import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/documents_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/router/router.dart';
import 'document_upload_sheet.dart';
import 'share_claim_sheet.dart';

/// Item detail screen with accordion sections (Screen 6.1/6.2).
///
/// Shows:
/// - Hero section (category icon + name + warranty status card)
/// - Collapsible Details section
/// - Collapsible Documents section
/// - Collapsible Claim Help section
/// - Collapsible Notes section
class ItemDetailScreen extends ConsumerWidget {
  final String itemId;

  const ItemDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetailProvider(itemId));

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/items/$itemId/edit'),
          ),
          _OverflowMenu(itemId: itemId),
        ],
      ),
      body: itemAsync.when(
        data: (item) => _ItemDetailBody(item: item, itemId: itemId),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            ErrorHandler.getUserMessage(error),
            style: const TextStyle(color: HavenColors.expired),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overflow menu (Archive / Delete)
// ---------------------------------------------------------------------------

class _OverflowMenu extends ConsumerWidget {
  final String itemId;

  const _OverflowMenu({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      color: HavenColors.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HavenRadius.card),
      ),
      onSelected: (value) async {
        switch (value) {
          case 'archive':
            final confirmed = await showHavenConfirmDialog(
              context,
              title: 'Archive item?',
              body:
                  'This item will be moved to your archive. You can restore it later.',
              confirmLabel: 'Archive',
            );
            if (confirmed && context.mounted) {
              try {
                await ref.read(itemsProvider.notifier).archiveItem(itemId);
                if (context.mounted) {
                  showHavenSnackBar(context, message: 'Item archived');
                  context.go(AppRoutes.items);
                }
              } catch (e) {
                if (context.mounted) {
                  showHavenSnackBar(context, message: ErrorHandler.getUserMessage(e));
                }
              }
            }
            break;
          case 'delete':
            final confirmed = await showHavenConfirmDialog(
              context,
              title: 'Delete item?',
              body:
                  'This action cannot be undone. All data for this item will be permanently removed.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (confirmed && context.mounted) {
              try {
                await ref.read(itemsProvider.notifier).deleteItem(itemId);
                if (context.mounted) {
                  showHavenSnackBar(context, message: 'Item deleted');
                  context.go(AppRoutes.items);
                }
              } catch (e) {
                if (context.mounted) {
                  showHavenSnackBar(context, message: ErrorHandler.getUserMessage(e));
                }
              }
            }
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'archive',
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 20, color: HavenColors.textSecondary),
              SizedBox(width: HavenSpacing.sm),
              Text('Archive'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: HavenColors.expired),
              SizedBox(width: HavenSpacing.sm),
              Text('Delete', style: TextStyle(color: HavenColors.expired)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main body
// ---------------------------------------------------------------------------

class _ItemDetailBody extends ConsumerWidget {
  final Item item;
  final String itemId;

  static final _claimHelpKey = GlobalKey();

  const _ItemDetailBody({required this.item, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsForItemProvider(itemId));
    final theme = Theme.of(context);
    final status = item.computedWarrantyStatus;
    final days = item.computedDaysRemaining ?? 0;

    final statusColor = switch (status) {
      WarrantyStatus.active => HavenColors.active,
      WarrantyStatus.expiring => HavenColors.expiring,
      WarrantyStatus.expired => HavenColors.expired,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(HavenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----------------------------------------------------------------
          // Hero section (always visible)
          // ----------------------------------------------------------------

          // Hero section with category icon + warranty status integrated
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: HavenColors.elevated,
              borderRadius: BorderRadius.circular(HavenRadius.card),
            ),
            child: Column(
              children: [
                // Category icon
                Padding(
                  padding: const EdgeInsets.only(top: HavenSpacing.xl),
                  child: CategoryIcon.widget(item.category, size: 64),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Warranty status badge (prominent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HavenSpacing.md,
                    vertical: HavenSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(HavenRadius.chip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        status == WarrantyStatus.active
                            ? Icons.check_circle
                            : status == WarrantyStatus.expiring
                                ? Icons.schedule
                                : Icons.cancel,
                        size: 16,
                        color: statusColor,
                      ),
                      const SizedBox(width: HavenSpacing.xs),
                      Text(
                        _buildTimeRemainingText(status, days),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Expiry date (always visible)
                if (item.warrantyEndDate != null) ...[
                  const SizedBox(height: HavenSpacing.sm),
                  Text(
                    status == WarrantyStatus.expired
                        ? 'Expired ${_formatDate(item.warrantyEndDate!)}'
                        : 'Expires ${_formatDate(item.warrantyEndDate!)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: HavenColors.textSecondary,
                    ),
                  ),
                ],

                const SizedBox(height: HavenSpacing.lg),
              ],
            ),
          ),

          const SizedBox(height: HavenSpacing.md),

          // Item name
          Text(
            [if (item.brand != null) item.brand!, item.name]
                .join(' '),
            style: theme.textTheme.headlineMedium,
          ),

          // Model number
          if (item.modelNumber != null) ...[
            const SizedBox(height: HavenSpacing.xs),
            Text(
              item.modelNumber!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: HavenColors.textSecondary,
              ),
            ),
          ],

          const SizedBox(height: HavenSpacing.md),

          // Claim button — opens the Claim Help accordion with guidance
          Padding(
            padding: const EdgeInsets.only(bottom: HavenSpacing.md),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  context.push('/warranty-claims/create/$itemId');
                },
                icon: const Icon(Icons.support_agent, size: 20),
                label: const Text('Start a Warranty Claim'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.primary,
                  side: const BorderSide(color: HavenColors.primary),
                ),
              ),
            ),
          ),

          // Warranty details card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.elevated,
              borderRadius: BorderRadius.circular(HavenRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'WARRANTY'),
                const SizedBox(height: HavenSpacing.sm),
                // Purchase info
                Text(
                  'Purchased: ${_formatDate(item.purchaseDate)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: HavenSpacing.xs),
                Text(
                  'Duration: ${_formatDuration(item.warrantyMonths)}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (item.warrantyProvider != null) ...[
                  const SizedBox(height: HavenSpacing.xs),
                  Text(
                    'Provider: ${item.warrantyProvider}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: HavenSpacing.xs),
                Text(
                  'Type: ${item.warrantyType.displayLabel}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // ----------------------------------------------------------------
          // DETAILS accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Details',
            initiallyExpanded: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Column(
                children: [
                  _DetailRow('Brand', item.brand),
                  _DetailRow('Model', item.modelNumber),
                  _DetailRow('Serial', item.serialNumber),
                  _DetailRow('Category', item.category.displayLabel),
                  _DetailRow('Room', item.room?.displayLabel),
                  _DetailRow(
                    'Price',
                    item.price != null
                        ? '\$${item.price!.toStringAsFixed(2)}'
                        : null,
                  ),
                  _DetailRow('Store', item.store),
                  _DetailRow('Warranty', item.warrantyType.displayLabel),
                  _DetailRow('Provider', item.warrantyProvider),
                ],
              ),
            ),
          ),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // DOCUMENTS accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Documents',
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: HavenSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: HavenColors.surface,
                borderRadius: BorderRadius.circular(HavenRadius.chip),
              ),
              child: Text(
                '${docsAsync.value?.length ?? 0}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textTertiary,
                ),
              ),
            ),
            initiallyExpanded:
                (docsAsync.value?.isNotEmpty ?? false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: docsAsync.when(
                data: (docs) => Column(
                  children: [
                    if (docs.isEmpty)
                      const Text(
                        'No documents yet',
                        style: TextStyle(color: HavenColors.textTertiary),
                      )
                    else
                      ...docs.map((doc) => _DocumentRow(
                            doc: doc,
                            itemId: itemId,
                          )),
                    const SizedBox(height: HavenSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () =>
                          DocumentUploadSheet.show(context, itemId),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Document'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HavenColors.secondary,
                        side: const BorderSide(color: HavenColors.border),
                      ),
                    ),
                  ],
                ),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(HavenSpacing.md),
                    child:
                        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
                error: (_, __) => const Text(
                  'Could not load documents',
                  style: TextStyle(color: HavenColors.expired),
                ),
              ),
            ),
          ),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // CLAIM HELP accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            key: _claimHelpKey,
            title: 'Claim Help',
            initiallyExpanded: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Step-by-step claim guidance
                  _ClaimStep(
                    number: 1,
                    title: 'Gather your documents',
                    description: 'You\'ll need your receipt, warranty card, and photos of the issue.',
                  ),
                  _ClaimStep(
                    number: 2,
                    title: 'Contact ${item.warrantyProvider ?? item.brand ?? 'the manufacturer'}',
                    description: 'Reach out via their website or phone to start the claim process.',
                  ),
                  const _ClaimStep(
                    number: 3,
                    title: 'Submit your claim',
                    description: 'Provide your proof of purchase, product details, and description of the issue.',
                  ),
                  const _ClaimStep(
                    number: 4,
                    title: 'Track your claim',
                    description: 'Keep your claim reference number and follow up if you don\'t hear back within 5-7 business days.',
                  ),
                  const SizedBox(height: HavenSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () {
                      final brand = item.brand ?? item.name;
                      final query = Uri.encodeComponent('$brand warranty support contact');
                      final searchUrl = 'https://www.google.com/search?q=$query';
                      launchUrl(Uri.parse(searchUrl), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(
                      'Find ${item.brand ?? item.name} Support Page',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.secondary,
                      side: const BorderSide(color: HavenColors.border),
                      padding: const EdgeInsets.symmetric(
                        vertical: HavenSpacing.sm + 4,
                        horizontal: HavenSpacing.md,
                      ),
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () {
                      ShareClaimSheet.show(context, item);
                    },
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share Claim Info'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.secondary,
                      side: const BorderSide(color: HavenColors.border),
                      padding: const EdgeInsets.symmetric(
                        vertical: HavenSpacing.sm + 4,
                        horizontal: HavenSpacing.md,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // NOTES accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Notes',
            initiallyExpanded: item.notes != null && item.notes!.isNotEmpty,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Text(
                item.notes != null && item.notes!.isNotEmpty
                    ? item.notes!
                    : 'No notes yet',
                style: TextStyle(
                  color: item.notes != null && item.notes!.isNotEmpty
                      ? HavenColors.textPrimary
                      : HavenColors.textTertiary,
                ),
              ),
            ),
          ),

          // Bottom spacing
          const SizedBox(height: HavenSpacing.xxl),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  String _buildTimeRemainingText(WarrantyStatus status, int days) {
    switch (status) {
      case WarrantyStatus.active:
        final months = days ~/ 30;
        if (months > 0) {
          return '$months ${months == 1 ? 'month' : 'months'} remaining';
        }
        return '$days ${days == 1 ? 'day' : 'days'} remaining';
      case WarrantyStatus.expiring:
        return '$days ${days == 1 ? 'day' : 'days'} remaining';
      case WarrantyStatus.expired:
        final absDays = days.abs();
        return 'Expired $absDays ${absDays == 1 ? 'day' : 'days'} ago';
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  String _formatDuration(int months) {
    if (months >= 12 && months % 12 == 0) {
      final years = months ~/ 12;
      return '$years ${years == 1 ? 'year' : 'years'}';
    }
    if (months >= 12) {
      final years = months ~/ 12;
      final rem = months % 12;
      return '$years ${years == 1 ? 'year' : 'years'} $rem ${rem == 1 ? 'month' : 'months'}';
    }
    return '$months ${months == 1 ? 'month' : 'months'}';
  }
}

// ---------------------------------------------------------------------------
// Document row within accordion
// ---------------------------------------------------------------------------

class _DocumentRow extends ConsumerStatefulWidget {
  final Document doc;
  final String itemId;

  const _DocumentRow({required this.doc, required this.itemId});

  @override
  ConsumerState<_DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends ConsumerState<_DocumentRow> {
  bool _isDeletingDocument = false;

  Document get doc => widget.doc;
  String get itemId => widget.itemId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: GestureDetector(
        onTap: () {
          // Open fullscreen image viewer
          showDialog(
            context: context,
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  doc.fileName,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              body: Center(
                child: InteractiveViewer(
                  child: Image.network(
                    doc.fileUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          color: HavenColors.primary,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.broken_image,
                        size: 120,
                        color: HavenColors.textTertiary,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
        onLongPress: () async {
          if (_isDeletingDocument) return;
          final confirmed = await showHavenConfirmDialog(
            context,
            title: 'Delete document?',
            body: 'Remove "${doc.fileName}"? This cannot be undone.',
            confirmLabel: 'Delete',
            isDestructive: true,
          );
          if (confirmed && context.mounted) {
            setState(() => _isDeletingDocument = true);
            try {
              await deleteDocument(
                ref,
                documentId: doc.id,
                itemId: itemId,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Document deleted')),
                );
              }
            } finally {
              if (mounted) {
                setState(() => _isDeletingDocument = false);
              }
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.all(HavenSpacing.sm),
          decoration: BoxDecoration(
            color: HavenColors.surface,
            borderRadius: BorderRadius.circular(HavenRadius.button),
            border: Border.all(color: HavenColors.border),
          ),
          child: Row(
            children: [
              DocumentTypeIcon.widget(doc.type, size: 22),
              const SizedBox(width: HavenSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.fileName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: HavenColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${doc.type.displayLabel} · ${doc.fileSizeFormatted}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new,
                size: 16,
                color: HavenColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail row (two-column label / value)
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: HavenColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '\u2014', // em-dash for null
              style: const TextStyle(
                fontSize: 14,
                color: HavenColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Claim step widget for guided claim help
// ---------------------------------------------------------------------------

class _ClaimStep extends StatelessWidget {
  final int number;
  final String title;
  final String description;

  const _ClaimStep({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: HavenColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HavenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: HavenColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
