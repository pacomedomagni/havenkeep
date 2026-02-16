import 'package:shared_models/shared_models.dart';

/// Strategies for resolving conflicts when same item edited on multiple devices.
enum ConflictResolutionStrategy {
  /// Keep the local version (client wins).
  keepLocal,

  /// Keep the server version (server wins).
  keepServer,

  /// Merge changes field by field (requires user decision).
  merge,

  /// Keep the version with the most recent update timestamp.
  mostRecent,
}

/// Represents a conflict between local and server versions of an entity.
class Conflict<T> {
  /// The local version of the entity.
  final T localVersion;

  /// The server version of the entity.
  final T serverVersion;

  /// The last known synced version (if available).
  final T? baseVersion;

  /// Timestamp when conflict was detected.
  final DateTime detectedAt;

  Conflict({
    required this.localVersion,
    required this.serverVersion,
    this.baseVersion,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();
}

/// Resolves conflicts between local and server versions of entities.
///
/// LIMITATION: Conflict detection relies solely on comparing `updatedAt`
/// timestamps between local and server versions. The server clock is
/// considered authoritative. This means:
///
/// - Local clock drift can cause false positives (detecting a conflict when
///   none exists) or false negatives (missing a real conflict).
/// - If two edits happen within the same timestamp granularity (e.g., within
///   the same second), one may be silently overwritten.
/// - There is no vector clock or version counter to track causality; only
///   wall-clock ordering is used.
///
/// A more robust approach would use server-issued version numbers or ETags,
/// but for now timestamp-based detection is acceptable given the low
/// probability of concurrent offline edits to the same item.
class ConflictResolver {
  /// Detects if a conflict exists between local and server versions.
  ///
  /// A conflict exists when:
  /// 1. Both local and server versions have been modified
  /// 2. The modifications occurred after the last sync
  /// 3. The server version is newer than our local sync timestamp
  static bool hasConflict(Item local, Item server) {
    // If local and server have identical updatedAt, no conflict
    if (local.updatedAt.isAtSameMomentAs(server.updatedAt)) {
      return false;
    }

    // If server is older than local, no conflict (local is authoritative)
    if (server.updatedAt.isBefore(local.updatedAt)) {
      return false;
    }

    // Server is newer AND local has unsaved changes → conflict
    return true;
  }

  /// Resolves a conflict using the specified strategy.
  static Item resolveItem(
    Conflict<Item> conflict,
    ConflictResolutionStrategy strategy,
  ) {
    switch (strategy) {
      case ConflictResolutionStrategy.keepLocal:
        return conflict.localVersion;

      case ConflictResolutionStrategy.keepServer:
        return conflict.serverVersion;

      case ConflictResolutionStrategy.mostRecent:
        return _resolveMostRecent(conflict);

      case ConflictResolutionStrategy.merge:
        return _mergeItems(conflict);
    }
  }

  /// Resolves by keeping the version with the most recent timestamp.
  static Item _resolveMostRecent(Conflict<Item> conflict) {
    final localUpdated = conflict.localVersion.updatedAt;
    final serverUpdated = conflict.serverVersion.updatedAt;

    return serverUpdated.isAfter(localUpdated)
        ? conflict.serverVersion
        : conflict.localVersion;
  }

  /// Merges changes from both versions using three-way merge logic.
  ///
  /// For each field:
  /// - If only local changed → use local value
  /// - If only server changed → use server value
  /// - If both changed → use most recent (server wins on tie)
  static Item _mergeItems(Conflict<Item> conflict) {
    final local = conflict.localVersion;
    final server = conflict.serverVersion;
    final base = conflict.baseVersion;

    // If no base version, fall back to most recent
    if (base == null) {
      return _resolveMostRecent(conflict);
    }

    // Three-way merge: detect which side changed each field
    return local.copyWith(
      name: _mergeField(base.name, local.name, server.name, server.name),
      brand: _mergeField(base.brand, local.brand, server.brand, server.brand),
      modelNumber: _mergeField(
        base.modelNumber,
        local.modelNumber,
        server.modelNumber,
        server.modelNumber,
      ),
      serialNumber: _mergeField(
        base.serialNumber,
        local.serialNumber,
        server.serialNumber,
        server.serialNumber,
      ),
      category: _mergeField(
        base.category,
        local.category,
        server.category,
        server.category,
      ),
      room: _mergeField(base.room, local.room, server.room, server.room),
      purchaseDate: _mergeField(
        base.purchaseDate,
        local.purchaseDate,
        server.purchaseDate,
        server.purchaseDate,
      ),
      store: _mergeField(base.store, local.store, server.store, server.store),
      price: _mergeField(base.price, local.price, server.price, server.price),
      warrantyMonths: _mergeField(
        base.warrantyMonths,
        local.warrantyMonths,
        server.warrantyMonths,
        server.warrantyMonths,
      ),
      warrantyType: _mergeField(
        base.warrantyType,
        local.warrantyType,
        server.warrantyType,
        server.warrantyType,
      ),
      warrantyProvider: _mergeField(
        base.warrantyProvider,
        local.warrantyProvider,
        server.warrantyProvider,
        server.warrantyProvider,
      ),
      notes: _mergeField(base.notes, local.notes, server.notes, server.notes),
      isArchived: _mergeField(
        base.isArchived,
        local.isArchived,
        server.isArchived,
        server.isArchived,
      ),
      // Always use server's computed fields
      warrantyEndDate: server.warrantyEndDate,
      updatedAt: server.updatedAt, // Server timestamp wins
    );
  }

  /// Three-way merge for a single field.
  ///
  /// Returns:
  /// - localValue if only local changed
  /// - serverValue if only server changed
  /// - serverValue if both changed (server wins on conflicts)
  /// - baseValue if neither changed
  static T _mergeField<T>(
    T baseValue,
    T localValue,
    T serverValue,
    T defaultValue,
  ) {
    final localChanged = localValue != baseValue;
    final serverChanged = serverValue != baseValue;

    if (localChanged && !serverChanged) {
      // Only local changed → use local
      return localValue;
    } else if (!localChanged && serverChanged) {
      // Only server changed → use server
      return serverValue;
    } else if (localChanged && serverChanged) {
      // Both changed → server wins
      return serverValue;
    } else {
      // Neither changed → use base (should all be equal)
      return baseValue;
    }
  }

  /// Gets a human-readable description of changes between two items.
  static List<String> getChangedFields(Item before, Item after) {
    final changes = <String>[];

    if (before.name != after.name) {
      changes.add('Name: "${before.name}" → "${after.name}"');
    }
    if (before.brand != after.brand) {
      changes.add('Brand: "${before.brand ?? 'none'}" → "${after.brand ?? 'none'}"');
    }
    if (before.modelNumber != after.modelNumber) {
      changes.add(
        'Model: "${before.modelNumber ?? 'none'}" → "${after.modelNumber ?? 'none'}"',
      );
    }
    if (before.category != after.category) {
      changes.add(
        'Category: "${before.category.displayLabel}" → "${after.category.displayLabel}"',
      );
    }
    if (before.room != after.room) {
      changes.add(
        'Room: "${before.room?.displayLabel ?? 'none'}" → "${after.room?.displayLabel ?? 'none'}"',
      );
    }
    if (before.purchaseDate != after.purchaseDate) {
      changes.add(
        'Purchase Date: "${_formatDate(before.purchaseDate)}" → "${_formatDate(after.purchaseDate)}"',
      );
    }
    if (before.warrantyMonths != after.warrantyMonths) {
      changes.add(
        'Warranty: "${before.warrantyMonths} months" → "${after.warrantyMonths} months"',
      );
    }
    if (before.price != after.price) {
      changes.add(
        'Price: "\$${before.price?.toStringAsFixed(2) ?? 'none'}" → "\$${after.price?.toStringAsFixed(2) ?? 'none'}"',
      );
    }
    if (before.notes != after.notes) {
      changes.add('Notes changed');
    }

    return changes;
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Determines if auto-resolution is safe (no user input needed).
  ///
  /// Auto-resolution is safe when:
  /// - Only one side changed (clear winner)
  /// - Changes are compatible and don't conflict
  static bool canAutoResolve(Conflict<Item> conflict) {
    final base = conflict.baseVersion;
    if (base == null) {
      // Without base version, can't determine who changed what
      return false;
    }

    final localChanges = getChangedFields(base, conflict.localVersion);
    final serverChanges = getChangedFields(base, conflict.serverVersion);

    // If only one side changed, can auto-resolve
    if (localChanges.isEmpty && serverChanges.isNotEmpty) return true;
    if (serverChanges.isEmpty && localChanges.isNotEmpty) return true;

    // If both sides changed different fields, can auto-resolve via merge
    // (Check if any field was modified by BOTH sides)
    final hasFieldConflict = _hasFieldLevelConflict(
      conflict.baseVersion!,
      conflict.localVersion,
      conflict.serverVersion,
    );

    return !hasFieldConflict;
  }

  /// Checks if any individual field was modified by both local and server.
  static bool _hasFieldLevelConflict(Item base, Item local, Item server) {
    return _bothChanged(base.name, local.name, server.name) ||
        _bothChanged(base.brand, local.brand, server.brand) ||
        _bothChanged(base.modelNumber, local.modelNumber, server.modelNumber) ||
        _bothChanged(
          base.serialNumber,
          local.serialNumber,
          server.serialNumber,
        ) ||
        _bothChanged(base.category, local.category, server.category) ||
        _bothChanged(base.room, local.room, server.room) ||
        _bothChanged(
          base.purchaseDate,
          local.purchaseDate,
          server.purchaseDate,
        ) ||
        _bothChanged(base.store, local.store, server.store) ||
        _bothChanged(base.price, local.price, server.price) ||
        _bothChanged(
          base.warrantyMonths,
          local.warrantyMonths,
          server.warrantyMonths,
        ) ||
        _bothChanged(
          base.warrantyType,
          local.warrantyType,
          server.warrantyType,
        ) ||
        _bothChanged(
          base.warrantyProvider,
          local.warrantyProvider,
          server.warrantyProvider,
        ) ||
        _bothChanged(base.notes, local.notes, server.notes) ||
        _bothChanged(base.isArchived, local.isArchived, server.isArchived);
  }

  /// Checks if a field was changed by both local and server.
  static bool _bothChanged<T>(T base, T local, T server) {
    final localChanged = local != base;
    final serverChanged = server != base;
    return localChanged && serverChanged;
  }
}
