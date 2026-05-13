import 'package:flutter/material.dart';

import 'theme.dart';

/// The single bottom-sheet primitive for HavenKeep. Replaces the
/// `showModalBottomSheet(...)` boilerplate scattered across features
/// (filter pickers, sort menus, share intent, source selection).
///
/// Use sheets only for ephemeral, low-commitment choices — a quick
/// menu the user wants to dismiss after picking one option. Anything
/// with depth (settings → change password, item → edit) belongs as a
/// pushed route with a real back button + iOS swipe-back, NOT a sheet.
///
/// Built-in:
///   * Drag handle, snap-to-content height by default.
///   * Branded surface (`surfaceHigh` + sheen) so it visually matches the
///     rest of the design system.
///   * Optional fixed header (title + close affordance) — pass [title]
///     to get the standard layout, or omit it and pass [header] for a
///     custom shape.
///   * `safeArea` true by default so content doesn't slide under the
///     home indicator.
///
/// ```dart
/// HavenSheet.show<ItemSortMode>(
///   context: context,
///   title: 'Sort by',
///   child: SortOptionsView(),
/// );
/// ```
class HavenSheet {
  HavenSheet._();

  /// Show a [HavenSheet] over the given [context]. Returns whatever
  /// [Navigator.pop] receives from inside the sheet, typed as [T].
  ///
  /// Pass [title] for the standard header (title + close icon).
  /// Pass [header] for a custom header widget (overrides [title]).
  /// Pass [child] for the content. [child] receives the standard side
  /// padding ([HavenSpacing.md]); use [padded: false] to opt out.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    Widget? header,
    bool padded = true,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: (ctx) => _HavenSheetBody(
        title: title,
        header: header,
        padded: padded,
        child: child,
      ),
    );
  }
}

class _HavenSheetBody extends StatelessWidget {
  final String? title;
  final Widget? header;
  final Widget child;
  final bool padded;

  const _HavenSheetBody({
    required this.child,
    required this.padded,
    this.title,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final radius = const BorderRadius.vertical(
      top: Radius.circular(HavenRadius.card + 4),
    );

    final resolvedHeader = header ??
        (title == null
            ? null
            : _DefaultSheetHeader(title: title!));

    return Container(
      decoration: BoxDecoration(
        color: HavenColors.surfaceHigh,
        borderRadius: radius,
        border: Border.all(color: HavenColors.borderHairline),
        boxShadow: HavenElevation.shadowFor(3),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: HavenElevation.sheen(strength: 1.2),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: HavenSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _DragHandle(),
                  if (resolvedHeader != null) resolvedHeader,
                  Flexible(
                    child: padded
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HavenSpacing.md,
                            ),
                            child: child,
                          )
                        : child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: HavenSpacing.sm, bottom: HavenSpacing.sm),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: HavenColors.textTertiary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _DefaultSheetHeader extends StatelessWidget {
  final String title;
  const _DefaultSheetHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HavenSpacing.md,
        HavenSpacing.xs,
        HavenSpacing.sm,
        HavenSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: HavenText.titleLarge),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 22),
            color: HavenColors.textSecondary,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
