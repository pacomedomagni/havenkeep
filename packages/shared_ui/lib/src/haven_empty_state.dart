import 'package:flutter/material.dart';

import 'haven_button.dart';
import 'theme.dart';

/// The single empty-state primitive for HavenKeep. Every "no warranties
/// yet", "no claims yet", "no notifications" surface routes through this
/// widget — same layout, same rhythm, every time.
///
/// Five slots:
///   * [icon] — a 56px illustration / icon in a softly tinted disc.
///   * [iconColor] — overrides the disc tint. Defaults to brand primary.
///   * [title] — the headline, [HavenText.displayMedium].
///   * [body] — supporting copy, [HavenText.bodySecondary].
///   * [primaryAction] / [secondaryAction] — optional CTAs.
///
/// Animates in with a gentle fade + 12px slide so the screen doesn't feel
/// abrupt the first time a user lands on a blank surface. Subsequent
/// rebuilds reuse the same widget state so the animation only fires once.
///
/// ```dart
/// HavenEmptyState(
///   icon: Icons.shield_outlined,
///   title: 'No warranties yet',
///   body: 'Add your first item to start tracking warranties, receipts, '
///         'and maintenance.',
///   primaryAction: HavenEmptyAction(
///     label: 'Add item',
///     icon: Icons.add,
///     onPressed: () => context.push('/items/add'),
///   ),
/// )
/// ```
class HavenEmptyState extends StatefulWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String body;
  final HavenEmptyAction? primaryAction;
  final HavenEmptyAction? secondaryAction;

  /// Tighter vertical padding for empty states inside a card / sheet.
  /// Default expands to fill the available height.
  final bool compact;

  const HavenEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.iconColor,
    this.primaryAction,
    this.secondaryAction,
    this.compact = false,
  });

  @override
  State<HavenEmptyState> createState() => _HavenEmptyStateState();
}

class _HavenEmptyStateState extends State<HavenEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: HavenMotion.slow,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: HavenMotion.standard));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.iconColor ?? HavenColors.primary;

    final inner = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: tint.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Icon(widget.icon, size: 36, color: tint),
        ),
        const SizedBox(height: HavenSpacing.lg),
        Text(
          widget.title,
          style: HavenText.displayMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HavenSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            widget.body,
            style: HavenText.bodySecondary,
            textAlign: TextAlign.center,
          ),
        ),
        if (widget.primaryAction != null || widget.secondaryAction != null) ...[
          const SizedBox(height: HavenSpacing.lg),
          if (widget.primaryAction != null)
            HavenButton.primary(
              label: widget.primaryAction!.label,
              onPressed: widget.primaryAction!.onPressed,
              leadingIcon: widget.primaryAction!.icon,
              size: HavenButtonSize.md,
            ),
          if (widget.secondaryAction != null) ...[
            const SizedBox(height: HavenSpacing.sm),
            HavenButton.tertiary(
              label: widget.secondaryAction!.label,
              onPressed: widget.secondaryAction!.onPressed,
              leadingIcon: widget.secondaryAction!.icon,
              size: HavenButtonSize.md,
            ),
          ],
        ],
      ],
    );

    final animated = FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: inner),
    );

    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.all(HavenSpacing.lg),
        child: animated,
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HavenSpacing.xl),
        child: animated,
      ),
    );
  }
}

/// A CTA paired with a [HavenEmptyState]. Just the data — the empty state
/// renders the actual button.
class HavenEmptyAction {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const HavenEmptyAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });
}
