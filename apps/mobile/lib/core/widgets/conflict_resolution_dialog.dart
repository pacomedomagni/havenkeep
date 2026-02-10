import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../utils/conflict_resolver.dart';

/// Dialog for resolving conflicts between local and server versions.
class ConflictResolutionDialog extends StatelessWidget {
  final Conflict<Item> conflict;
  final VoidCallback? onKeepLocal;
  final VoidCallback? onKeepServer;
  final VoidCallback? onMerge;

  const ConflictResolutionDialog({
    super.key,
    required this.conflict,
    this.onKeepLocal,
    this.onKeepServer,
    this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final local = conflict.localVersion;
    final server = conflict.serverVersion;
    final base = conflict.baseVersion;

    final localChanges = base != null
        ? ConflictResolver.getChangedFields(base, local)
        : <String>[];
    final serverChanges = base != null
        ? ConflictResolver.getChangedFields(base, server)
        : <String>[];

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Sync Conflict Detected',
              style: TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This item was modified on multiple devices. Choose which version to keep:',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 20),
            _buildVersionCard(
              context,
              title: 'Your Changes (This Device)',
              subtitle: 'Last modified: ${_formatTimestamp(local.updatedAt)}',
              changes: localChanges,
              icon: Icons.phone_android,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildVersionCard(
              context,
              title: 'Server Version (Other Device)',
              subtitle: 'Last modified: ${_formatTimestamp(server.updatedAt)}',
              changes: serverChanges,
              icon: Icons.cloud,
              color: Colors.green,
            ),
            if (base != null && localChanges.isNotEmpty && serverChanges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber[900], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Merge will combine changes from both versions.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onKeepServer?.call();
          },
          child: const Text('Keep Server'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onKeepLocal?.call();
          },
          child: const Text('Keep Mine'),
        ),
        if (base != null)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onMerge?.call();
            },
            child: const Text('Merge Both'),
          ),
      ],
    );
  }

  Widget _buildVersionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<String> changes,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (changes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Changes:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...changes.map((change) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: TextStyle(color: color)),
                            Expanded(
                              child: Text(
                                change,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No changes',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    }
  }

  /// Shows the conflict resolution dialog.
  static Future<ConflictResolutionStrategy?> show(
    BuildContext context,
    Conflict<Item> conflict,
  ) async {
    ConflictResolutionStrategy? result;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConflictResolutionDialog(
        conflict: conflict,
        onKeepLocal: () => result = ConflictResolutionStrategy.keepLocal,
        onKeepServer: () => result = ConflictResolutionStrategy.keepServer,
        onMerge: () => result = ConflictResolutionStrategy.merge,
      ),
    );

    return result;
  }
}

/// Simplified conflict notification banner.
class ConflictNotificationBanner extends StatelessWidget {
  final int conflictCount;
  final VoidCallback onResolve;

  const ConflictNotificationBanner({
    super.key,
    required this.conflictCount,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border(
          bottom: BorderSide(color: Colors.orange[200]!),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$conflictCount ${conflictCount == 1 ? 'conflict' : 'conflicts'} detected',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[900],
                  ),
                ),
                Text(
                  'Items were modified on multiple devices',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onResolve,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange[700],
            ),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }
}
