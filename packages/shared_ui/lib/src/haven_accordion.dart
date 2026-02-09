import 'package:flutter/material.dart';
import 'theme.dart';

/// A collapsible section widget with animated expand/collapse.
///
/// Displays a header row with a small-caps title, optional trailing widget,
/// and an animated chevron icon. Tapping the header toggles the visibility
/// of [child] using a cross-fade animation.
class HavenAccordion extends StatefulWidget {
  const HavenAccordion({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyExpanded = false,
  });

  /// The section title, displayed in small-caps (uppercase, 12px bold).
  final String title;

  /// Optional widget displayed after the title (e.g., a count badge).
  final Widget? trailing;

  /// Whether the accordion starts in the expanded state.
  final bool initiallyExpanded;

  /// The content revealed when the accordion is expanded.
  final Widget child;

  @override
  State<HavenAccordion> createState() => _HavenAccordionState();
}

class _HavenAccordionState extends State<HavenAccordion> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm),
            child: Row(
              children: [
                Text(
                  widget.title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: HavenSpacing.sm),
                  widget.trailing!,
                ],
                const Spacer(),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: HavenColors.textTertiary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          color: HavenColors.border,
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: widget.child,
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}
