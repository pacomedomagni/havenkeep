import 'package:flutter/material.dart';

import 'theme.dart';

/// Visual style of a [HavenListItem].
enum HavenListItemStyle {
  /// Default — flush row with a hairline divider underneath. Use inside a
  /// [HavenCard] or grouped section where the parent gives the container
  /// shape.
  inline,

  /// Standalone card — each row is its own [HavenCard.surface]. Use for
  /// items list, claims list, gifts list — anywhere rows breathe.
  card,
}

/// The single list-row primitive for HavenKeep. Replaces every hand-rolled
/// `Row(...)` + `Container(decoration: ...)` row scattered across items,
/// claims, notifications, maintenance, settings.
///
/// Six visual slots — anything outside this shape is the wrong widget:
///   * [leading] — icon / avatar / thumbnail (40px square reserve).
///   * [title]   — primary line, [HavenText.titleMedium].
///   * [subtitle] — secondary line, [HavenText.meta].
///   * [supplementary] — optional third line for low-priority metadata.
///   * [trailing] — badge / chevron / overflow menu.
///   * [accent]  — optional 3px left stripe (status color).
///
/// The whole row is a single tap target with the standard
/// [HavenCard] press-scale + branded ripple. Use [onLongPress] for
/// contextual actions (multi-select, rename).
///
/// ```dart
/// HavenListItem(
///   leading: const CategoryIcon(category),
///   title: 'Whirlpool washer',
///   subtitle: 'Laundry · expires 2027-03-04',
///   trailing: WarrantyStatusBadge(status),
///   onTap: () => context.push('/items/$id'),
/// )
/// ```
class HavenListItem extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? supplementary;
  final Widget? trailing;
  final Color? accent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HavenListItemStyle style;
  final bool selected;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  const HavenListItem({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.supplementary,
    this.trailing,
    this.accent,
    this.onTap,
    this.onLongPress,
    this.style = HavenListItemStyle.card,
    this.selected = false,
    this.padding,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final pad = padding ??
        const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md,
          vertical: HavenSpacing.md - 2,
        );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (accent != null)
          Container(
            width: 3,
            height: 40,
            margin: const EdgeInsets.only(right: HavenSpacing.sm + 4),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        if (leading != null) ...[
          SizedBox(
            width: 40,
            height: 40,
            child: Center(child: leading),
          ),
          const SizedBox(width: HavenSpacing.md - 4),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: HavenText.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: HavenText.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (supplementary != null) ...[
                const SizedBox(height: 2),
                Text(
                  supplementary!,
                  style: HavenText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: HavenSpacing.sm + 4),
          trailing!,
        ],
      ],
    );

    final radius = BorderRadius.circular(HavenRadius.card);
    final selectedOutline = selected
        ? HavenColors.primary
        : (style == HavenListItemStyle.card
            ? HavenColors.border
            : HavenColors.borderHairline);

    if (style == HavenListItemStyle.inline) {
      // Inline rows live inside a parent that already has the card chrome.
      // We render a plain padded row + ink, no decoration of our own.
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          child: Semantics(
            button: onTap != null,
            label: semanticLabel ?? title,
            child: Padding(padding: pad, child: row),
          ),
        ),
      );
    }

    // Card style — each row is its own surface.
    final decoration = BoxDecoration(
      color: selected
          ? HavenColors.primary.withValues(alpha: 0.10)
          : HavenColors.surface,
      borderRadius: radius,
      border: Border.all(color: selectedOutline, width: selected ? 1.5 : 1),
      boxShadow: HavenElevation.shadowFor(1),
    );

    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: HavenElevation.sheen(strength: 0.9),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: radius,
              child: Semantics(
                button: onTap != null,
                label: semanticLabel ?? title,
                child: Padding(padding: pad, child: row),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
