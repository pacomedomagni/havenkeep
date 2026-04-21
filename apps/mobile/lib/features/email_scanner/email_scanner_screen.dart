import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/email_scanner_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../main.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_loader.dart';

/// Screen to initiate email scans and view scan history.
class EmailScannerScreen extends ConsumerWidget {
  const EmailScannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scansAsync = ref.watch(emailScansProvider);
    final config = ref.watch(environmentConfigProvider);
    final importedItemsAsync = ref.watch(emailImportedItemsProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Email Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(emailScansProvider.notifier).refresh(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(HavenSpacing.md),
        children: [
          const _InfoCard(
            title: 'Import purchases from your inbox',
            body:
                'Connect Gmail or Outlook to scan for purchase receipts and '
                'auto-create warranties.',
          ),
          const SizedBox(height: HavenSpacing.sm),
          const _PrivacyCard(),
          const SizedBox(height: HavenSpacing.md),
          _ProviderButtons(
            outlookEnabled: config.outlookClientId.isNotEmpty &&
                config.outlookRedirectUri.isNotEmpty,
            onGmail: () => _startScan(context, ref, 'gmail'),
            onOutlook: () => _startScan(context, ref, 'outlook'),
          ),
          const SizedBox(height: HavenSpacing.lg),

          // Receipt Import Summary
          importedItemsAsync.when(
            data: (importedItems) {
              if (importedItems.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'RECEIPTS IMPORTED'),
                  const SizedBox(height: HavenSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(HavenSpacing.md),
                    decoration: BoxDecoration(
                      color: HavenColors.surface,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                      border: Border.all(color: HavenColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                              color: HavenColors.primary,
                            ),
                            const SizedBox(width: HavenSpacing.sm),
                            Text(
                              '${importedItems.length} item${importedItems.length == 1 ? '' : 's'} imported from email',
                              style: const TextStyle(
                                color: HavenColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: HavenSpacing.sm),
                        ...importedItems.take(5).map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const SizedBox(width: 26),
                                Expanded(
                                  child: Text(
                                    item.brand != null
                                        ? '${item.brand} ${item.name}'
                                        : item.name,
                                    style: const TextStyle(
                                      color: HavenColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (importedItems.length > 5) ...[
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 26),
                            child: Text(
                              '+ ${importedItems.length - 5} more',
                              style: const TextStyle(
                                color: HavenColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.lg),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SectionHeader(title: 'SCAN HISTORY'),
          const SizedBox(height: HavenSpacing.sm),
          scansAsync.when(
            data: (scans) {
              if (scans.isEmpty) {
                return const _EmptyState(
                  title: 'No scans yet',
                  subtitle: 'Start a scan to import receipts from email.',
                );
              }
              return Column(
                children: scans.map((scan) => _ScanCard(scan: scan)).toList(),
              );
            },
            loading: () => const _LoadingState(),
            error: (err, _) => _ErrorState(
              message: ErrorHandler.getUserMessage(err),
              onRetry: () => ref.read(emailScansProvider.notifier).refresh(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startScan(
    BuildContext context,
    WidgetRef ref,
    String provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    // 1. Pre-prime: explain exactly what we do and don't access.
    final proceed = await _showPrivacyPrime(context, provider);
    if (proceed != true) return;
    if (!context.mounted) return;

    // 2. Show staged progress dialog that advances through the scan steps.
    final progress = _ScanProgressController();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ScanProgressDialog(controller: progress),
      ),
    );

    try {
      progress.advance('Connecting to $provider…');
      final notifier = ref.read(emailScansProvider.notifier);
      final token = await notifier.getAccessToken(provider);

      progress.advance('Searching your inbox for receipts…');
      await notifier.startScan(provider: provider, accessToken: token);

      progress.advance('Importing found receipts…');
      // Brief pause so the user can read the final stage.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Email scan started for $provider')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        messenger.showSnackBar(
          SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
        );
      }
    }
  }

  Future<bool?> _showPrivacyPrime(BuildContext context, String provider) {
    final providerLabel = provider == 'gmail' ? 'Gmail' : 'Outlook';
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: HavenColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
        ),
        title: Text('Connect $providerLabel'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PrivacyLine(icon: Icons.search, text: 'We scan only for purchase receipts.'),
            SizedBox(height: HavenSpacing.sm),
            _PrivacyLine(icon: Icons.lock_outline, text: 'Other emails are never read or stored.'),
            SizedBox(height: HavenSpacing.sm),
            _PrivacyLine(icon: Icons.logout, text: 'You can disconnect any time from Settings.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text('Connect $providerLabel'),
          ),
        ],
      ),
    );
  }
}

/// Lightweight progress controller for the scan dialog. Uses a
/// ValueNotifier so the dialog rebuilds on each advance without state ceremony.
class _ScanProgressController {
  final ValueNotifier<String> stage =
      ValueNotifier<String>('Preparing…');
  void advance(String label) => stage.value = label;
}

class _ScanProgressDialog extends StatelessWidget {
  final _ScanProgressController controller;
  const _ScanProgressDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: HavenColors.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HavenRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HavenSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HavenLoader(size: 40),
            const SizedBox(height: HavenSpacing.md),
            ValueListenableBuilder<String>(
              valueListenable: controller.stage,
              builder: (_, label, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: const TextStyle(
                    color: HavenColors.textPrimary,
                    fontSize: 15,
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

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(
            color: HavenColors.primary.withValues(alpha: 0.35)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.shield_outlined,
                color: HavenColors.primary, size: 18),
            SizedBox(width: HavenSpacing.sm),
            Text('How we protect your inbox',
                style: TextStyle(
                    color: HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ]),
          SizedBox(height: HavenSpacing.sm),
          _PrivacyLine(icon: Icons.search,
              text: 'We look only for purchase receipts.'),
          SizedBox(height: 6),
          _PrivacyLine(icon: Icons.visibility_off_outlined,
              text: 'We never read personal or unrelated messages.'),
          SizedBox(height: 6),
          _PrivacyLine(icon: Icons.logout,
              text: 'Disconnect any time from Settings.'),
        ],
      ),
    );
  }
}

class _PrivacyLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PrivacyLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: HavenColors.textTertiary, size: 16),
        const SizedBox(width: HavenSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                color: HavenColors.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.elevated,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: HavenColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            body,
            style: const TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderButtons extends StatelessWidget {
  final bool outlookEnabled;
  final VoidCallback onGmail;
  final VoidCallback onOutlook;

  const _ProviderButtons({
    required this.outlookEnabled,
    required this.onGmail,
    required this.onOutlook,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onGmail,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Scan Gmail'),
            style: ElevatedButton.styleFrom(
              backgroundColor: HavenColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: HavenSpacing.sm),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: outlookEnabled ? onOutlook : null,
            icon: const Icon(Icons.mark_email_unread_outlined),
            label: const Text('Scan Outlook'),
            style: ElevatedButton.styleFrom(
              backgroundColor: HavenColors.surface,
              foregroundColor: HavenColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanCard extends StatelessWidget {
  final EmailScan scan;

  const _ScanCard({required this.scan});

  @override
  Widget build(BuildContext context) {
    final status = scan.status;
    final statusColor = switch (status.name) {
      'completed' => HavenColors.active,
      'failed' => HavenColors.expired,
      'scanning' => HavenColors.expiring,
      _ => HavenColors.textTertiary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${scan.provider.toString().toUpperCase()} Scan',
                  style: const TextStyle(
                    color: HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HavenSpacing.sm,
                  vertical: HavenSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(HavenRadius.chip),
                ),
                child: Text(
                  scan.status.displayLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            'Scanned ${scan.emailsScanned} emails • '
            '${scan.receiptsFound} receipts • '
            '${scan.itemsImported} items',
            style: const TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            'Started ${DateFormat.yMMMd().add_jm().format(scan.scanDate)}',
            style: const TextStyle(
              color: HavenColors.textTertiary,
              fontSize: 11,
            ),
          ),
          if (scan.errorMessage != null) ...[
            const SizedBox(height: HavenSpacing.xs),
            Text(
              scan.errorMessage!,
              style: TextStyle(
                // Amber/warning for completed scans with a limit warning,
                // red for actual failures
                color: scan.status == EmailScanStatus.completed
                    ? HavenColors.expiring
                    : HavenColors.expired,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.lg),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        children: [
          const HavenIllustration(
            kind: HavenIllustrationKind.noScans,
            size: 140,
          ),
          const SizedBox(height: HavenSpacing.sm),
          Text(title, style: HavenText.titleLarge),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: HavenText.caption,
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(HavenSpacing.lg),
      child: Center(child: HavenLoader()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
