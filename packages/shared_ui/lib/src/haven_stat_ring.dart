import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A circular progress ring with a centered label — the "warranty health
/// 87%" dial. Animates the sweep in from zero on first build (and on value
/// change), with a rounded cap and a faint track behind. This is the kind
/// of crafted micro-element that makes a hero card read as designed rather
/// than assembled.
///
/// ```dart
/// HavenStatRing(
///   value: 0.87,                       // 0..1
///   size: 96,
///   color: HavenColors.active,
///   center: CountUpText(value: 87, suffix: '%', style: HavenText.stat),
///   label: 'Health',
/// )
/// ```
class HavenStatRing extends StatelessWidget {
  /// Progress, 0..1 (clamped).
  final double value;

  /// Outer diameter.
  final double size;

  /// Stroke thickness of the arc.
  final double strokeWidth;

  /// Arc color (the filled portion).
  final Color color;

  /// Track color (the unfilled remainder). Defaults to [color] @ 16%.
  final Color? trackColor;

  /// Widget centered inside the ring — typically the big number.
  final Widget? center;

  /// Optional small caption below the [center] (e.g. "Health").
  final String? label;

  /// Animation duration for the sweep-in.
  final Duration duration;

  const HavenStatRing({
    super.key,
    required this.value,
    this.size = 96,
    this.strokeWidth = 8,
    this.color = HavenColors.primary,
    this.trackColor,
    this.center,
    this.label,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          return CustomPaint(
            painter: _RingPainter(
              progress: t,
              color: color,
              trackColor: trackColor ?? color.withValues(alpha: 0.16),
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (center != null) center!,
                  if (label != null) ...[
                    const SizedBox(height: 1),
                    Text(label!, style: HavenText.caption),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // Track — full circle, faint.
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    // Progress arc — starts at 12 o'clock, sweeps clockwise. A subtle
    // sweep gradient (color → slightly lighter) gives the arc depth.
    const start = -math.pi / 2;
    final sweep = progress * math.pi * 2;
    final arc = Paint()
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + math.pi * 2,
        colors: [
          color,
          Color.lerp(color, Colors.white, 0.25)!,
          color,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, start, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}

/// Tweens an integer from 0 (or its previous value) up to [value] on build
/// — the dashboard's "$12,847" / "87%" count-up. Pair it with
/// [HavenStatRing.center] or use standalone for the hero number.
///
/// ```dart
/// CountUpText(value: 12847, prefix: '\$', style: HavenText.hero)
/// CountUpText(value: 87, suffix: '%', style: HavenText.stat)
/// ```
class CountUpText extends StatelessWidget {
  final num value;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration duration;

  /// Optional custom formatter for the tweened value. Defaults to
  /// `round().toString()` with thousands separators when the magnitude
  /// is ≥ 1000.
  final String Function(num current)? format;

  const CountUpText({
    super.key,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.textAlign,
    this.duration = const Duration(milliseconds: 800),
    this.format,
  });

  String _defaultFormat(num n) {
    final i = n.round();
    if (i.abs() < 1000) return '$i';
    final s = i.abs().toString();
    final buf = StringBuffer(i < 0 ? '-' : '');
    for (var idx = 0; idx < s.length; idx++) {
      if (idx > 0 && (s.length - idx) % 3 == 0) buf.write(',');
      buf.write(s[idx]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final body = (format ?? _defaultFormat)(t);
        return Text('$prefix$body$suffix', style: style, textAlign: textAlign);
      },
    );
  }
}
