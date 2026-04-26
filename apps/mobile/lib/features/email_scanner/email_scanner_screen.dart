import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/email_scanner_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/services/email_scanner_repository.dart';
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

          // Connected accounts (granted scopes + in-app disconnect).
          const _ConnectedAccountsSection(),

          // Low-confidence review queue.
          const _ReviewQueueSection(),

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
                children: scans
                    .map((scan) => _ScanCard(
                          scan: scan,
                          onCancel: scan.status == EmailScanStatus.scanning ||
                                  scan.status == EmailScanStatus.pending
                              ? () => _confirmAndCancelScan(context, ref, scan)
                              : null,
                        ))
                    .toList(),
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

  /// Confirm-and-cancel for an in-flight scan from the history card.
  /// Routes through the notifier which handles polling cleanup +
  /// server-side cancel + list refresh.
  Future<void> _confirmAndCancelScan(
    BuildContext context,
    WidgetRef ref,
    EmailScan scan,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: HavenColors.elevated,
        title: const Text('Cancel scan?'),
        content: const Text(
          'Stop this scan now. Receipts already imported are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep scanning'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: HavenColors.expired,
            ),
            child: const Text('Cancel scan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(emailScansProvider.notifier).cancelScan(scan.id);
      messenger.showSnackBar(const SnackBar(content: Text('Scan cancelled')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
      );
    }
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

    // 2. Show staged progress dialog. Track the dialog's local navigator
    // via a Completer-driven pop so we never call pop() against a route
    // that's already been backgrounded (F027/F030).
    final progress = _ScanProgressController();
    bool dialogClosed = false;
    final dialogContextCompleter = Completer<BuildContext>();

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          if (!dialogContextCompleter.isCompleted) {
            dialogContextCompleter.complete(dialogCtx);
          }
          return _ScanProgressDialog(controller: progress);
        },
      ),
    );

    void closeDialogIfOpen() {
      if (dialogClosed) return;
      dialogClosed = true;
      if (dialogContextCompleter.isCompleted) {
        // Use the captured dialog context to pop only that route, never the
        // page underneath it.
        dialogContextCompleter.future.then((dialogCtx) {
          if (!dialogCtx.mounted) return;
          final navigator = Navigator.of(dialogCtx);
          if (navigator.canPop()) {
            navigator.pop();
          }
        });
      }
    }

    try {
      progress.advance('Connecting to $provider…');
      final notifier = ref.read(emailScansProvider.notifier);
      final auth = await notifier.getAuthorizationCode(provider);

      progress.advance('Searching your inbox for receipts…');
      await notifier.startScan(
        provider: provider,
        code: auth.code,
        redirectUri: auth.redirectUri,
      );

      progress.advance('Importing found receipts…');
      // Brief pause so the user can read the final stage.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      closeDialogIfOpen();
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Email scan started for $provider')),
        );
      }
    } catch (e) {
      closeDialogIfOpen();
      if (context.mounted) {
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
        // Decorative icon — exclude from semantics so TalkBack doesn't
        // announce it alongside the adjacent text (F031).
        ExcludeSemantics(
          child: Icon(icon, color: HavenColors.textTertiary, size: 16),
        ),
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
  final VoidCallback? onCancel;

  const _ScanCard({required this.scan, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final status = scan.status;
    // Exhaustive over the EmailScanStatus enum so we don't quietly fall
    // through to "unknown" colors when the model adds a new state (F028).
    final statusColor = switch (status) {
      EmailScanStatus.completed => HavenColors.active,
      EmailScanStatus.failed => HavenColors.expired,
      EmailScanStatus.scanning => HavenColors.expiring,
      EmailScanStatus.pending => HavenColors.textTertiary,
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
          if (onCancel != null) ...[
            const SizedBox(height: HavenSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('Cancel scan'),
                style: TextButton.styleFrom(
                  foregroundColor: HavenColors.expired,
                  padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.sm),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Connected-accounts strip — lists each linked email integration with
/// the granted OAuth scopes and an in-app disconnect button. Closes the
/// audit gap that "Disconnect any time from Settings" was a claim with no
/// in-app surface backing it.
class _ConnectedAccountsSection extends ConsumerWidget {
  const _ConnectedAccountsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(emailIntegrationsProvider);
    return async.when(
      data: (integrations) {
        if (integrations.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'CONNECTED ACCOUNTS'),
            const SizedBox(height: HavenSpacing.sm),
            for (final i in integrations) _IntegrationCard(integration: i),
            const SizedBox(height: HavenSpacing.lg),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _IntegrationCard extends ConsumerWidget {
  final EmailIntegration integration;
  const _IntegrationCard({required this.integration});

  Future<void> _confirmDisconnect(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final providerLabel =
        integration.provider == 'gmail' ? 'Gmail' : 'Outlook';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: HavenColors.elevated,
        title: Text('Disconnect $providerLabel?'),
        content: Text(
          'We will stop scanning your $providerLabel inbox and revoke the '
          'OAuth tokens on the server. Already-imported items stay in your '
          'library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep connected'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: HavenColors.expired,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(emailScannerRepositoryProvider)
          .revokeIntegration(provider: integration.provider);
      ref.invalidate(emailIntegrationsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('$providerLabel disconnected')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerLabel =
        integration.provider == 'gmail' ? 'Gmail' : 'Outlook';
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
              Icon(
                integration.provider == 'gmail'
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined,
                color: HavenColors.primary,
                size: 18,
              ),
              const SizedBox(width: HavenSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      providerLabel,
                      style: const TextStyle(
                        color: HavenColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      integration.providerEmail,
                      style: const TextStyle(
                        color: HavenColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _confirmDisconnect(context, ref),
                style: TextButton.styleFrom(
                  foregroundColor: HavenColors.expired,
                ),
                child: const Text('Disconnect'),
              ),
            ],
          ),
          if (integration.grantedScopes.isNotEmpty) ...[
            const SizedBox(height: HavenSpacing.sm),
            const Text(
              'Granted scopes',
              style: TextStyle(
                color: HavenColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final scope in integration.grantedScopes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HavenColors.primary.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(HavenRadius.chip),
                    ),
                    child: Text(
                      _shortScope(scope),
                      style: const TextStyle(
                        color: HavenColors.primary,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Trim noisy OAuth scope URLs down to the trailing component so the
  /// chip stays readable (`gmail.readonly` instead of the full URL).
  String _shortScope(String scope) {
    final slashIdx = scope.lastIndexOf('/');
    if (slashIdx == -1) return scope;
    return scope.substring(slashIdx + 1);
  }
}

/// Low-confidence review-queue surface. Renders one card per pending row
/// with Approve / Reject controls; hides itself when the queue is empty
/// so the screen stays clean for the happy path.
class _ReviewQueueSection extends ConsumerWidget {
  const _ReviewQueueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(emailReviewQueueProvider);
    return async.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SectionHeader(title: 'REVIEW QUEUE'),
                const SizedBox(width: HavenSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: HavenColors.expiring.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(HavenRadius.chip),
                  ),
                  child: Text(
                    '${entries.length}',
                    style: const TextStyle(
                      color: HavenColors.expiring,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HavenSpacing.sm),
            for (final e in entries) _ReviewCard(entry: e),
            const SizedBox(height: HavenSpacing.lg),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  final EmailReviewQueueEntry entry;
  const _ReviewCard({required this.entry});

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _busy = false;

  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(emailScannerRepositoryProvider)
          .approveReview(widget.entry.id);
      ref.invalidate(emailReviewQueueProvider);
      ref.invalidate(emailImportedItemsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Receipt approved and item created')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(emailScannerRepositoryProvider)
          .rejectReview(widget.entry.id);
      ref.invalidate(emailReviewQueueProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Receipt rejected')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final confidencePct = (entry.confidenceScore * 100).round();
    // The AI-extracted purchase date lives inside `suggestedItem` rather
    // than as a top-level field; surface it when present so reviewers can
    // sanity-check the date before approving.
    final rawPurchaseDate = entry.suggestedItem['purchaseDate'] as String?;
    final purchaseDate = rawPurchaseDate == null
        ? null
        : DateTime.tryParse(rawPurchaseDate);
    return Container(
      margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.expiring.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.suggestedName,
                  style: const TextStyle(
                    color: HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HavenColors.expiring.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(HavenRadius.chip),
                ),
                child: Text(
                  '$confidencePct% match',
                  style: const TextStyle(
                    color: HavenColors.expiring,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            entry.suggestedBrand?.isNotEmpty == true
                ? '${entry.suggestedBrand} · ${entry.senderDomain}'
                : entry.senderDomain,
            style: const TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (purchaseDate != null) ...[
            const SizedBox(height: 2),
            Text(
              'Purchased ${DateFormat.yMMMd().format(purchaseDate)}',
              style: const TextStyle(
                color: HavenColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: HavenSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : _reject,
                style: TextButton.styleFrom(
                  foregroundColor: HavenColors.textSecondary,
                ),
                child: const Text('Reject'),
              ),
              const SizedBox(width: HavenSpacing.xs),
              ElevatedButton.icon(
                onPressed: _busy ? null : _approve,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 16),
                label: const Text('Approve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HavenColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
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
