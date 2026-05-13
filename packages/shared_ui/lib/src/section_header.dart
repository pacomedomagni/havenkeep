import 'package:flutter/material.dart';
import 'theme.dart';

/// A small-caps section label used to visually separate groups of content.
///
/// Displays the [title] in uppercase with optional [count] badge and
/// [trailing] widget. If [onTap] is provided the entire header becomes
/// tappable. Use [SectionHeader.display] for the larger "screen-section"
/// headers (a heading + optional subtitle) instead of hand-rolling a
/// [Column] of [Text] widgets.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.onTap,
  })  : subtitle = null,
        _isDisplay = false;

  /// Screen-level section header — bigger, bolder, optional subtitle.
  /// Renders as [HavenText.displayMedium] over [HavenText.bodySecondary].
  /// Use as the "Your warranties", "Recent activity" header on the
  /// dashboard / a feature screen.
  const SectionHeader.display({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  })  : count = null,
        _isDisplay = true;

  /// The section title. For [SectionHeader] (default) this is rendered in
  /// uppercase small-caps; for [SectionHeader.display] it is rendered as
  /// [HavenText.displayMedium].
  final String title;

  /// Optional item count displayed in parentheses after the title.
  /// Only used by the default constructor.
  final int? count;

  /// Optional one-line description rendered below the title. Only used by
  /// [SectionHeader.display].
  final String? subtitle;

  /// Optional widget placed at the trailing end of the row (e.g., an action
  /// button or icon).
  final Widget? trailing;

  /// Optional tap handler; when provided, wraps the header in an [InkWell].
  final VoidCallback? onTap;

  final bool _isDisplay;

  static const _labelStyle = HavenText.overline;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_isDisplay) {
      content = Padding(
        padding: const EdgeInsets.only(bottom: HavenSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: HavenText.displayMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: HavenText.bodySecondary),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: HavenSpacing.sm),
              trailing!,
            ],
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
        child: Row(
          children: [
            Text.rich(
              TextSpan(
                text: title.toUpperCase(),
                children: [
                  if (count != null) TextSpan(text: ' ($count)'),
                ],
              ),
              style: _labelStyle,
            ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
    }

    if (onTap != null) {
      return Semantics(
        button: true,
        label: title,
        child: InkWell(
          onTap: onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}
