import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/documents_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/providers/maintenance_provider.dart';
import '../maintenance/log_maintenance_screen.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/router/router.dart';
import '../../core/widgets/responsive_box.dart';
import 'document_upload_sheet.dart';
import 'share_claim_sheet.dart';
import '../../core/widgets/haven_image.dart';
import '../../core/widgets/haven_loader.dart';

/// Item detail screen with accordion sections (Screen 6.1/6.2).
///
/// Shows:
/// - Hero section (category icon + name + warranty status card)
/// - Collapsible Details section
/// - Tabbed Documents section (one tab per [DocumentType])
/// - Inline recent maintenance card
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
          // Share intent — only meaningful once we have an item loaded.
          itemAsync.maybeWhen(
            data: (item) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share warranty',
              onPressed: () => _shareItem(context, item),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          _OverflowMenu(itemId: itemId),
        ],
      ),
      body: itemAsync.when(
        data: (item) => _ItemDetailBody(item: item, itemId: itemId),
        loading: () => const Center(child: HavenLoader()),
        error: (error, _) => Center(
          child: Text(
            ErrorHandler.getUserMessage(error),
            style: const TextStyle(color: HavenColors.expired),
          ),
        ),
      ),
    );
  }

  /// Share the item via the OS share sheet.
  ///
  /// Builds the same tagline regardless of platform: brand + name +
  /// purchase date + warranty status. Falls back to the marketing root
  /// for the deep link until `/items/:id` exists on havenkeep.com (the
  /// link is informational — the recipient can't open the warranty
  /// without an account).
  static Future<void> _shareItem(BuildContext context, Item item) async {
    final messenger = ScaffoldMessenger.of(context);
    final formattedDate = DateFormat.yMMMd().format(item.purchaseDate);
    final status = item.computedWarrantyStatus;
    final days = item.computedDaysRemaining;
    final warrantyLine = switch (status) {
      WarrantyStatus.active =>
        'warranty active for ${_humanDays(days)} more',
      WarrantyStatus.expiring => 'warranty expiring in ${_humanDays(days)}',
      WarrantyStatus.expired => 'warranty expired ${_humanDays(days.abs())} ago',
    };

    final brand = (item.brand ?? '').trim();
    final namePart = brand.isEmpty ? item.name : '$brand ${item.name}';
    final shareUrl = 'https://havenkeep.com/items/${item.id}';
    final text =
        '$namePart — purchased $formattedDate, $warrantyLine. Tracked in HavenKeep. $shareUrl';

    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: namePart),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
      );
    }
  }

  static String _humanDays(int days) {
    if (days >= 30) {
      final months = days ~/ 30;
      return '$months ${months == 1 ? 'month' : 'months'}';
    }
    return '$days ${days == 1 ? 'day' : 'days'}';
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
        // Capture parent messenger before any pop — the item detail's own
        // messenger is gone once we navigate back. (F046)
        final messenger = ScaffoldMessenger.of(context);
        switch (value) {
          case 'archive':
            final confirmed = await showHavenConfirmDialog(
              context,
              title: 'Archive warranty?',
              body:
                  'This warranty will be moved to your archive. You can restore it later.',
              confirmLabel: 'Archive',
            );
            if (confirmed && context.mounted) {
              try {
                await ref.read(itemsProvider.notifier).archiveItem(itemId);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Warranty archived')),
                );
                if (!context.mounted) break;
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.items);
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
                );
              }
            }
            break;
          case 'delete':
            final confirmed = await showHavenConfirmDialog(
              context,
              title: 'Delete warranty?',
              body:
                  'This action cannot be undone. All data for this warranty will be permanently removed.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (confirmed && context.mounted) {
              try {
                await ref.read(itemsProvider.notifier).deleteItem(itemId);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Warranty deleted')),
                );
                if (!context.mounted) break;
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.items);
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
                );
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

  const _ItemDetailBody({required this.item, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = item.computedWarrantyStatus;
    final days = item.computedDaysRemaining;

    final statusColor = switch (status) {
      WarrantyStatus.active => HavenColors.active,
      WarrantyStatus.expiring => HavenColors.expiring,
      WarrantyStatus.expired => HavenColors.expired,
    };

    return ResponsiveBox(
      child: SingleChildScrollView(
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
                  child: Hero(
                    tag: 'item-icon-${item.id}',
                    child: CategoryIcon.widget(item.category, size: 64),
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Warranty status badge (prominent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HavenSpacing.md,
                    vertical: HavenSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
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

                // Expiry date (always visible — generated NOT NULL on the API
                // side after Ch08-Item-D010).
                const SizedBox(height: HavenSpacing.sm),
                Text(
                  status == WarrantyStatus.expired
                      ? 'Expired ${_formatDate(item.warrantyEndDate)}'
                      : 'Expires ${_formatDate(item.warrantyEndDate)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: HavenColors.textSecondary,
                  ),
                ),

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
                    item.price != null ? Money.format(item.price) : null,
                  ),
                  _DetailRow('Store', item.store),
                  _DetailRow('Warranty', item.warrantyType.displayLabel),
                  _DetailRow('Provider', item.warrantyProvider),
                  if (item.estimatedRepairCost != null)
                    _DetailRow(
                      'Typical Repair Cost',
                      Money.formatWhole(item.estimatedRepairCost),
                    ),
                ],
              ),
            ),
          ),

          // ----------------------------------------------------------------
          // LIFESPAN TRACKING section
          // ----------------------------------------------------------------
          if (item.lifespanPercentage != null) ...[
            const SizedBox(height: HavenSpacing.sm),
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
                  const SectionHeader(title: 'LIFESPAN'),
                  const SizedBox(height: HavenSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(HavenRadius.micro),
                    child: LinearProgressIndicator(
                      value: item.lifespanPercentage! / 100.0,
                      minHeight: 8,
                      backgroundColor: HavenColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        item.lifespanPercentage! < 50
                            ? Colors.green
                            : item.lifespanPercentage! <= 80
                                ? Colors.amber
                                : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  Text(
                    '${item.lifespanPercentage}% of estimated ${item.expectedLifespanYears ?? "?"}-year lifespan',
                    style: const TextStyle(
                      fontSize: 13,
                      color: HavenColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // DOCUMENTS — tabbed by type
          // ----------------------------------------------------------------

          DocumentTabsCard(itemId: itemId),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // RECENT MAINTENANCE — last 3 entries for this item
          // ----------------------------------------------------------------

          RecentMaintenanceCard(itemId: itemId),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // CLAIM HELP accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Claim Help',
            initiallyExpanded: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Step-by-step claim guidance
                  const _ClaimStep(
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
                    onPressed: () async {
                      // Wrap in canLaunchUrl + snackbar fallback (F049).
                      final messenger = ScaffoldMessenger.of(context);
                      final brand = item.brand ?? item.name;
                      final query = Uri.encodeComponent('$brand warranty support contact');
                      final searchUri = Uri.parse('https://www.google.com/search?q=$query');
                      if (await canLaunchUrl(searchUri)) {
                        await launchUrl(searchUri, mode: LaunchMode.externalApplication);
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Could not open browser.')),
                        );
                      }
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
// DocumentTabsCard — tabbed view of documents grouped by [DocumentType].
// ---------------------------------------------------------------------------

/// Renders a `TabBar` over the five [DocumentType] values. Each tab shows
/// thumbnails of documents matching that type with an empty-state CTA when
/// the bucket is empty. Scroll position is preserved per tab via a
/// [PageStorageBucket] so flicking back and forth doesn't reset the list.
class DocumentTabsCard extends ConsumerStatefulWidget {
  final String itemId;

  const DocumentTabsCard({super.key, required this.itemId});

  @override
  ConsumerState<DocumentTabsCard> createState() => _DocumentTabsCardState();
}

class _DocumentTabsCardState extends ConsumerState<DocumentTabsCard>
    with SingleTickerProviderStateMixin {
  /// Tab order — the all-up entry sits first so users land on the full
  /// list, with type-scoped tabs behind it.
  static const _tabs = <DocumentType?>[
    null, // "All"
    DocumentType.receipt,
    DocumentType.warranty_card,
    DocumentType.manual,
    DocumentType.invoice,
    DocumentType.other,
  ];

  late final TabController _controller;
  final PageStorageBucket _bucket = PageStorageBucket();

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsForItemProvider(widget.itemId));

    return Container(
      decoration: BoxDecoration(
        color: HavenColors.elevated,
        borderRadius: BorderRadius.circular(HavenRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HavenSpacing.md,
              HavenSpacing.md,
              HavenSpacing.md,
              0,
            ),
            child: Row(
              children: [
                const SectionHeader(title: 'DOCUMENTS'),
                const Spacer(),
                Container(
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
              ],
            ),
          ),
          TabBar(
            controller: _controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: HavenColors.primary,
            unselectedLabelColor: HavenColors.textSecondary,
            indicatorColor: HavenColors.primary,
            tabs: _tabs.map((type) {
              return Tab(
                text: type == null ? 'All' : type.displayLabel,
              );
            }).toList(),
          ),
          docsAsync.when(
            loading: () => const SizedBox(
              height: 140,
              child: Center(
                child: SizedBox(width: 24, height: 24, child: HavenLoader()),
              ),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(HavenSpacing.md),
              child: Text(
                'Could not load documents',
                style: TextStyle(color: HavenColors.expired),
              ),
            ),
            data: (allDocs) {
              return SizedBox(
                height: 280,
                child: PageStorage(
                  bucket: _bucket,
                  child: TabBarView(
                    controller: _controller,
                    children: _tabs.map((type) {
                      final docs = type == null
                          ? allDocs
                          : allDocs.where((d) => d.type == type).toList();
                      return _DocumentBucket(
                        key: PageStorageKey('docs-${type?.name ?? 'all'}'),
                        docs: docs,
                        type: type,
                        itemId: widget.itemId,
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DocumentBucket extends StatelessWidget {
  final List<Document> docs;
  final DocumentType? type;
  final String itemId;

  const _DocumentBucket({
    super.key,
    required this.docs,
    required this.type,
    required this.itemId,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      final label = type?.displayLabel.toLowerCase() ?? 'document';
      return Padding(
        padding: const EdgeInsets.all(HavenSpacing.lg),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                type == null
                    ? Icons.folder_open_outlined
                    : DocumentTypeIcon.get(type!),
                size: 36,
                color: HavenColors.textTertiary,
              ),
              const SizedBox(height: HavenSpacing.sm),
              Text(
                'No ${label}s yet',
                style: const TextStyle(color: HavenColors.textTertiary),
              ),
              const SizedBox(height: HavenSpacing.md),
              OutlinedButton.icon(
                onPressed: () => DocumentUploadSheet.show(
                  context,
                  itemId,
                  initialType: type,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  type == null
                      ? 'Add Document'
                      : 'Upload your first $label',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.secondary,
                  side: const BorderSide(color: HavenColors.border),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(HavenSpacing.md),
      children: [
        ...docs.map((doc) => _DocumentRow(doc: doc, itemId: itemId)),
        const SizedBox(height: HavenSpacing.sm),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => DocumentUploadSheet.show(
              context,
              itemId,
              initialType: type,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(type == null ? 'Add Document' : 'Add ${type!.displayLabel}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: HavenColors.secondary,
              side: const BorderSide(color: HavenColors.border),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// RecentMaintenanceCard — last 3 entries for the item with a "View all" link.
// ---------------------------------------------------------------------------

class RecentMaintenanceCard extends ConsumerWidget {
  final String itemId;

  const RecentMaintenanceCard({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(maintenanceHistoryByItemProvider(itemId));
    final dateFormat = DateFormat.yMMMd();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.elevated,
        borderRadius: BorderRadius.circular(HavenRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionHeader(title: 'RECENT MAINTENANCE'),
              const Spacer(),
              IconButton(
                tooltip: 'Customize schedule',
                icon: const Icon(Icons.tune,
                    size: 18, color: HavenColors.secondary),
                onPressed: () => context.push(
                  AppRoutes.customizeSchedule.replaceAll(':itemId', itemId),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              historyAsync.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? const SizedBox.shrink()
                    : TextButton(
                        onPressed: () => context.push(
                          '${AppRoutes.maintenanceHistory}?item_id=$itemId',
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: HavenSpacing.sm,
                          ),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text(
                          'View all',
                          style: TextStyle(color: HavenColors.secondary),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: HavenSpacing.sm),
          historyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: HavenLoader()),
              ),
            ),
            error: (_, __) => const Text(
              'Could not load maintenance history',
              style: TextStyle(color: HavenColors.expired),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: HavenSpacing.sm,
                      ),
                      child: Text(
                        'No maintenance logged yet',
                        style: TextStyle(color: HavenColors.textTertiary),
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => LogMaintenanceScreen.showAsSheet(
                        context,
                        itemId: itemId,
                      ),
                      icon: const Icon(Icons.add_task, size: 18),
                      label: const Text('Log maintenance'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HavenColors.secondary,
                        side: const BorderSide(color: HavenColors.border),
                      ),
                    ),
                  ],
                );
              }
              final recent = entries.take(3).toList();
              return Column(
                children: [
                  for (final entry in recent) ...[
                    _MaintenanceRow(entry: entry, dateFormat: dateFormat),
                    if (entry != recent.last)
                      const Divider(
                        height: 1,
                        color: HavenColors.border,
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MaintenanceRow extends StatelessWidget {
  final MaintenanceHistory entry;
  final DateFormat dateFormat;

  const _MaintenanceRow({required this.entry, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 18,
            color: HavenColors.active,
          ),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.taskName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: HavenColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dateFormat.format(entry.completedDate),
                  style: const TextStyle(
                    fontSize: 12,
                    color: HavenColors.textTertiary,
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

  Future<void> _confirmAndDelete() async {
    if (_isDeletingDocument) return;
    final confirmed = await showHavenConfirmDialog(
      context,
      title: 'Delete document?',
      body: 'Remove "${doc.fileName}"? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;
    // Capture messenger BEFORE any further async hop so success/failure
    // can still be surfaced if the row is removed from the tree (F047).
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isDeletingDocument = true);
    try {
      await deleteDocument(
        ref,
        documentId: doc.id,
        itemId: itemId,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Document deleted')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingDocument = false);
      }
    }
  }

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
              // Wrap in SafeArea so the status bar / home indicator
              // doesn't overlap the image at the edges (F048).
              body: SafeArea(
                child: Center(
                  child: InteractiveViewer(
                    child: HavenImage(
                      url: doc.fileUrl,
                      fit: BoxFit.contain,
                      errorFallback: const Icon(
                        Icons.broken_image,
                        size: 120,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        onLongPress: _confirmAndDelete,
        child: Container(
          padding: const EdgeInsets.all(HavenSpacing.sm),
          decoration: BoxDecoration(
            color: HavenColors.surface,
            borderRadius: BorderRadius.circular(HavenRadius.button),
            border: Border.all(color: HavenColors.border),
          ),
          child: Row(
            children: [
              // Thumbnail (image) or type icon (PDF / DOC).
              ClipRRect(
                borderRadius: BorderRadius.circular(HavenRadius.micro),
                child: doc.isImage
                    ? HavenImage(
                        url: doc.thumbnailUrl ?? doc.fileUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorFallback: DocumentTypeIcon.widget(doc.type, size: 22),
                      )
                    : Container(
                        width: 40,
                        height: 40,
                        color: HavenColors.elevated,
                        child: Center(
                          child: DocumentTypeIcon.widget(doc.type, size: 22),
                        ),
                      ),
              ),
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
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: HavenColors.textTertiary,
                ),
                tooltip: 'Delete document',
                onPressed: _isDeletingDocument ? null : _confirmAndDelete,
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
    final hasValue = value != null && value!.isNotEmpty;
    // Semantics overrides the em-dash so screen readers say "Not set" rather
    // than reading the raw em-dash character (F051).
    return Semantics(
      label: '$label: ${hasValue ? value : 'Not set'}',
      child: ExcludeSemantics(
        child: Padding(
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
                  hasValue ? value! : '—',
                  style: const TextStyle(
                    fontSize: 14,
                    color: HavenColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
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
