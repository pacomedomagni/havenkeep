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
class HavenListItem extends StatefulWidget {
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

  /// Zero-based position in the visible list. When set, the row stagger-
  /// fades in (40ms cascade per index). Leave null inside lists where
  /// rows can reorder/filter — the animation is only worth firing on
  /// first paint of a stable list.
  final int? entryIndex;

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
    this.entryIndex,
  });

  @override
  State<HavenListItem> createState() => _HavenListItemState();
}

class _HavenListItemState extends State<HavenListItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _entry;
  Animation<double>? _opacity;
  Animation<Offset>? _slide;

  @override
  void initState() {
    super.initState();
    if (widget.entryIndex != null) {
      _entry = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 360),
      );
      _opacity =
          CurvedAnimation(parent: _entry!, curve: Curves.easeOut);
      _slide = Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _entry!, curve: HavenMotion.standard));
      // Cap stagger at 12 rows — anything past that and the user is
      // waiting on choreography instead of seeing their list.
      final staggerIndex = widget.entryIndex!.clamp(0, 12);
      Future<void>.delayed(
        Duration(milliseconds: staggerIndex * 40),
        () {
          if (mounted) _entry!.forward();
        },
      );
    }
  }

  @override
  void dispose() {
    _entry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.padding ??
        const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md,
          vertical: HavenSpacing.md - 2,
        );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.accent != null)
          Container(
            width: 3,
            height: 40,
            margin: const EdgeInsets.only(right: HavenSpacing.sm + 4),
            decoration: BoxDecoration(
              color: widget.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        if (widget.leading != null) ...[
          SizedBox(
            width: 40,
            height: 40,
            child: Center(child: widget.leading),
          ),
          const SizedBox(width: HavenSpacing.md - 4),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: HavenText.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: HavenText.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (widget.supplementary != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.supplementary!,
                  style: HavenText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: HavenSpacing.sm + 4),
          widget.trailing!,
        ],
      ],
    );

    final radius = BorderRadius.circular(HavenRadius.card);
    final selectedOutline = widget.selected
        ? HavenColors.primary
        : (widget.style == HavenListItemStyle.card
            ? HavenColors.border
            : HavenColors.borderHairline);

    Widget content;
    if (widget.style == HavenListItemStyle.inline) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: radius,
          child: Semantics(
            button: widget.onTap != null,
            label: widget.semanticLabel ?? widget.title,
            child: Padding(padding: pad, child: row),
          ),
        ),
      );
    } else {
      // Card style — each row is its own surface.
      final decoration = BoxDecoration(
        color: widget.selected
            ? HavenColors.primary.withValues(alpha: 0.10)
            : HavenColors.surface,
        borderRadius: radius,
        border: Border.all(
          color: selectedOutline,
          width: widget.selected ? 1.5 : 1,
        ),
        boxShadow: HavenElevation.shadowFor(1),
      );

      content = DecoratedBox(
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
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                borderRadius: radius,
                child: Semantics(
                  button: widget.onTap != null,
                  label: widget.semanticLabel ?? widget.title,
                  child: Padding(padding: pad, child: row),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Wrap in staggered entry animation if entryIndex is set.
    if (_entry != null && _opacity != null && _slide != null) {
      return FadeTransition(
        opacity: _opacity!,
        child: SlideTransition(position: _slide!, child: content),
      );
    }
    return content;
  }
}
