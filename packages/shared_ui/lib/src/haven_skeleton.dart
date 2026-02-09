import 'package:flutter/material.dart';
import 'theme.dart';

/// Internal base widget that provides the shimmer opacity animation.
///
/// All skeleton placeholders wrap this widget to share a single
/// [AnimationController] pattern: opacity oscillates between 0.3 and 0.7
/// over 1500ms with an ease-in-out curve, repeating in reverse.
class _SkeletonBase extends StatefulWidget {
  const _SkeletonBase({
    required this.child,
  });

  /// The child widget whose opacity is animated.
  final Widget child;

  @override
  State<_SkeletonBase> createState() => _SkeletonBaseState();
}

class _SkeletonBaseState extends State<_SkeletonBase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _opacity = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: widget.child,
    );
  }
}

/// A single animated line placeholder used for text loading states.
///
/// Renders a rounded rectangle in [HavenColors.elevated] with a pulsing
/// opacity animation. Use [width] to control the line length (defaults to
/// full available width) and [height] for thickness (defaults to 16).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 16,
  });

  /// The width of the line. If null, expands to fill available width.
  final double? width;

  /// The height (thickness) of the line.
  final double height;

  @override
  Widget build(BuildContext context) {
    return _SkeletonBase(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: HavenColors.elevated,
          borderRadius: BorderRadius.circular(HavenRadius.input),
        ),
      ),
    );
  }
}

/// A rectangular placeholder for images or larger content areas.
///
/// Renders a rounded rectangle in [HavenColors.elevated] with the same
/// pulsing opacity animation as [SkeletonLine]. Both [width] and [height]
/// are required.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
  });

  /// The width of the box.
  final double width;

  /// The height of the box.
  final double height;

  @override
  Widget build(BuildContext context) {
    return _SkeletonBase(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: HavenColors.elevated,
          borderRadius: BorderRadius.circular(HavenRadius.input),
        ),
      ),
    );
  }
}

/// A full card-sized placeholder that mimics the layout of a content card.
///
/// Renders a [HavenColors.surface] container with a border, containing
/// multiple [SkeletonLine] widgets at varying widths to suggest a loading
/// card with a title, subtitle, and body text.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonLine(width: 180, height: 18),
          SizedBox(height: HavenSpacing.sm),
          SkeletonLine(height: 14),
          SizedBox(height: HavenSpacing.sm),
          SkeletonLine(width: 240, height: 14),
          SizedBox(height: HavenSpacing.sm),
          SkeletonLine(width: 120, height: 14),
        ],
      ),
    );
  }
}
