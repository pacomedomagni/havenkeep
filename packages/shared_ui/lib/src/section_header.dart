import 'package:flutter/material.dart';
import 'theme.dart';

/// A small-caps section label used to visually separate groups of content.
///
/// Displays the [title] in uppercase with optional [count] badge and
/// [trailing] widget. If [onTap] is provided the entire header becomes
/// tappable.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.onTap,
  });

  /// The section title, rendered in uppercase small-caps style.
  final String title;

  /// Optional item count displayed in parentheses after the title.
  final int? count;

  /// Optional widget placed at the trailing end of the row (e.g., an action
  /// button or icon).
  final Widget? trailing;

  /// Optional tap handler; when provided, wraps the header in an [InkWell].
  final VoidCallback? onTap;

  static const _labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: HavenColors.textTertiary,
    letterSpacing: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              text: title.toUpperCase(),
              children: [
                if (count != null)
                  TextSpan(text: ' ($count)'),
              ],
            ),
            style: _labelStyle,
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}
