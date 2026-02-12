import 'package:flutter/material.dart';
import 'theme.dart';

/// Internal base widget that provides a shimmer animation.
///
/// All skeleton placeholders wrap this widget. A gradient highlight
/// sweeps across the child from left to right, creating a shimmer effect
/// on top of the base opacity pulse.
class _SkeletonBase extends StatefulWidget {
  const _SkeletonBase({
    required this.child,
  });

  final Widget child;

  @override
  State<_SkeletonBase> createState() => _SkeletonBaseState();
}

class _SkeletonBaseState extends State<_SkeletonBase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0x00FFFFFF),
                Color(0x33FFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: Opacity(
        opacity: 0.5,
        child: widget.child,
      ),
    );
  }
}

/// A single animated line placeholder used for text loading states.
///
/// Renders a rounded rectangle in [HavenColors.elevated] with a shimmer
/// animation. Use [width] to control the line length (defaults to
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
/// shimmer animation as [SkeletonLine]. Both [width] and [height]
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
