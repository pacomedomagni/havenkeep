import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Branded indeterminate loader — a pulsing indigo arc in HavenKeep's
/// primary gradient. Use this everywhere you'd otherwise reach for
/// `CircularProgressIndicator`.
///
/// ```dart
/// HavenLoader()                           // default, 32px
/// HavenLoader(size: 48)                   // custom size
/// HavenLoader.small()                     // 20px, for inline
/// HavenLoader(color: Colors.white)        // override tint on dark card
/// ```
class HavenLoader extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color? color;

  const HavenLoader({
    super.key,
    this.size = 32,
    this.strokeWidth = 3,
    this.color,
  });

  const HavenLoader.small({super.key, this.color})
      : size = 20,
        strokeWidth = 2.5;

  const HavenLoader.large({super.key, this.color})
      : size = 56,
        strokeWidth = 4;

  @override
  State<HavenLoader> createState() => _HavenLoaderState();
}

class _HavenLoaderState extends State<HavenLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color ?? HavenColors.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _HavenLoaderPainter(
              progress: _controller.value,
              color: tint,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _HavenLoaderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _HavenLoaderPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;

    // Faint track
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Rotating arc with sweep that grows/shrinks for a breathing feel.
    final sweep = math.pi + math.sin(progress * math.pi * 2) * (math.pi / 2);
    final start = progress * math.pi * 2 - math.pi / 2;

    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withValues(alpha: 0.0),
          color,
          color,
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(start),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HavenLoaderPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
