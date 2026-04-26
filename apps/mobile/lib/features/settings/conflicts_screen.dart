import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/database/database.dart';
import '../../core/providers/items_provider.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/widgets/haven_loader.dart';

/// Resolution UI for sync conflicts parked by [OfflineSyncService].
///
/// When an offline `update_item` push hits a 409, the service writes the
/// local + server JSON snapshots into the `sync_conflicts` table instead
/// of silently last-write-winning. This screen lists every parked
/// conflict, shows local vs server side-by-side, and lets the user pick
/// a winner — the choice is then pushed back to the API and the row is
/// dropped from the local table.
class ConflictsScreen extends ConsumerWidget {
  const ConflictsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictsAsync = ref.watch(openSyncConflictsProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Sync Conflicts'),
      ),
      body: conflictsAsync.when(
        loading: () => const Center(child: HavenLoader()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Text(
              'Could not load conflicts: $e',
              style: const TextStyle(color: HavenColors.expired),
            ),
          ),
        ),
        data: (conflicts) {
          if (conflicts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(HavenSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: HavenColors.active,
                    ),
                    SizedBox(height: HavenSpacing.sm),
                    Text(
                      'All synced',
                      style: HavenText.titleLarge,
                    ),
                    SizedBox(height: HavenSpacing.xs),
                    Text(
                      'No conflicts to resolve.',
                      style: HavenText.bodySecondary,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(HavenSpacing.md),
            itemCount: conflicts.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: HavenSpacing.md),
            itemBuilder: (context, index) =>
                _ConflictCard(conflict: conflicts[index]),
          );
        },
      ),
    );
  }
}

class _ConflictCard extends ConsumerStatefulWidget {
  const _ConflictCard({required this.conflict});

  final SyncConflict conflict;

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  bool _resolving = false;
  String? _error;

  Future<void> _resolve({required bool keepLocal}) async {
    setState(() {
      _resolving = true;
      _error = null;
    });

    try {
      // Only `item` conflicts are parked today (the only mutation the
      // sync queue runs through ConflictResolver). Decode unconditionally
      // and adjust if more entity types start getting parked.
      if (widget.conflict.entityType != 'item') {
        throw StateError(
          'Unsupported conflict entity type: ${widget.conflict.entityType}',
        );
      }

      final winningJson = keepLocal
          ? jsonDecode(widget.conflict.localVersionJson)
              as Map<String, dynamic>
          : jsonDecode(widget.conflict.serverVersionJson)
              as Map<String, dynamic>;
      final winning = Item.fromJson(winningJson);

      final repo = ref.read(itemsRepositoryProvider);
      if (keepLocal) {
        // Push the local copy as the new authoritative version.
        await repo.updateItem(winning);
      }
      // For both branches: drop the local cached row of the conflicting
      // item before invalidating the provider. Without this, the local
      // SQLite still holds the loser, and an offline edit made between
      // resolution and the next API re-fetch would build on the stale
      // baseline and trigger the same 409 on next sync. Removing the
      // row forces the next read of itemsProvider to repopulate from
      // the API (which is now authoritative on either branch).
      final db = ref.read(localDatabaseProvider);
      await db.removeItem(winning.id);
      await db.removeConflict(widget.conflict.id);

      // Refresh the conflict count + list for the UI.
      ref.read(syncConflictCountProvider.notifier).state =
          await db.getConflictCount();
      ref.invalidate(openSyncConflictsProvider);
      ref.invalidate(itemsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            keepLocal ? 'Kept your version' : 'Kept the server version',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to resolve: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Map<String, dynamic> _decode(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = _decode(widget.conflict.localVersionJson);
    final server = _decode(widget.conflict.serverVersionJson);
    final dateFmt = DateFormat.yMMMd().add_jm();

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
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: HavenColors.expiring,
                size: 20,
              ),
              const SizedBox(width: HavenSpacing.sm),
              Expanded(
                child: Text(
                  '${widget.conflict.entityType.toUpperCase()} ${_truncId(widget.conflict.entityId)}',
                  style: HavenText.titleMedium,
                ),
              ),
              Text(
                dateFmt.format(widget.conflict.createdAt.toLocal()),
                style: HavenText.caption,
              ),
            ],
          ),
          const SizedBox(height: HavenSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _VersionColumn(
                  title: 'Yours (this device)',
                  json: local,
                  highlight: HavenColors.primary,
                ),
              ),
              const SizedBox(width: HavenSpacing.md),
              Expanded(
                child: _VersionColumn(
                  title: 'Server (other device)',
                  json: server,
                  highlight: HavenColors.active,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: HavenSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(
                color: HavenColors.expired,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: HavenSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _resolving ? null : () => _resolve(keepLocal: false),
                child: const Text('Keep server'),
              ),
              const SizedBox(width: HavenSpacing.xs),
              FilledButton(
                onPressed: _resolving ? null : () => _resolve(keepLocal: true),
                child: _resolving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: HavenLoader(color: Colors.white),
                      )
                    : const Text('Keep mine'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _truncId(String id) =>
      id.length > 8 ? '${id.substring(0, 8)}…' : id;
}

/// A single column showing the salient fields from a version snapshot.
/// We deliberately render a small subset (name / brand / price /
/// updated-at / notes) instead of the full JSON so the user can compare
/// at a glance.
class _VersionColumn extends StatelessWidget {
  const _VersionColumn({
    required this.title,
    required this.json,
    required this.highlight,
  });

  final String title;
  final Map<String, dynamic> json;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    String fmtDate(dynamic raw) {
      if (raw == null) return '—';
      try {
        final dt = DateTime.parse(raw.toString()).toLocal();
        return DateFormat.yMMMd().add_jm().format(dt);
      } catch (_) {
        return raw.toString();
      }
    }

    final fields = <(String, String)>[
      ('Name', (json['name'] ?? '—').toString()),
      ('Brand', (json['brand'] ?? '—').toString()),
      (
        'Price',
        json['price'] == null
            ? '—'
            : '\$${(json['price'] as num).toStringAsFixed(2)}',
      ),
      ('Notes', (json['notes'] ?? '—').toString()),
      ('Updated', fmtDate(json['updatedAt'] ?? json['updated_at'])),
    ];

    return Container(
      padding: const EdgeInsets.all(HavenSpacing.sm),
      decoration: BoxDecoration(
        color: highlight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(HavenRadius.button),
        border: Border.all(color: highlight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: HavenText.caption.copyWith(
              color: highlight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: HavenSpacing.xs),
          for (final field in fields) ...[
            Text(
              field.$1,
              style: HavenText.caption,
            ),
            Text(
              field.$2,
              style: HavenText.bodySecondary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: HavenSpacing.xs),
          ],
        ],
      ),
    );
  }
}
