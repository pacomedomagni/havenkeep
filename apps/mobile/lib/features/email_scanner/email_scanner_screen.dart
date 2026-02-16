import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/email_scanner_provider.dart';
import '../../main.dart';

/// Screen to initiate email scans and view scan history.
class EmailScannerScreen extends ConsumerWidget {
  const EmailScannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scansAsync = ref.watch(emailScansProvider);
    final config = ref.watch(environmentConfigProvider);

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
          _InfoCard(
            title: 'Import purchases from your inbox',
            body:
                'Connect Gmail or Outlook to scan for purchase receipts and '
                'auto-create items.',
          ),
          const SizedBox(height: HavenSpacing.md),
          _ProviderButtons(
            outlookEnabled: config.outlookClientId.isNotEmpty &&
                config.outlookRedirectUri.isNotEmpty,
            onGmail: () => _startScan(context, ref, 'gmail'),
            onOutlook: () => _startScan(context, ref, 'outlook'),
          ),
          const SizedBox(height: HavenSpacing.lg),
          const SectionHeader(title: 'SCAN HISTORY'),
          const SizedBox(height: HavenSpacing.sm),
          scansAsync.when(
            data: (scans) {
              if (scans.isEmpty) {
                return _EmptyState(
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
              message: 'Failed to load scans: $err',
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final notifier = ref.read(emailScansProvider.notifier);
      final token = await notifier.getAccessToken(provider);
      await notifier.startScan(provider: provider, accessToken: token);

      if (context.mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Email scan started for $provider')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
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
                  color: statusColor.withOpacity(0.15),
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
              style: const TextStyle(
                color: HavenColors.expired,
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
          const Icon(Icons.inbox_outlined, color: HavenColors.textTertiary),
          const SizedBox(height: HavenSpacing.sm),
          Text(
            title,
            style: const TextStyle(
              color: HavenColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 12,
            ),
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
      child: Center(child: CircularProgressIndicator()),
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
