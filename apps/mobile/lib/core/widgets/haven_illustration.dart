import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Illustration slots shipped natively (no external SVG) so empty states
/// stop looking like placeholder Material icons.
///
/// Each illustration is a `CustomPaint` drawing in the brand gradient
/// (indigo → violet) with gold/active accents where appropriate.
enum HavenIllustrationKind {
  /// Empty vault / nothing-to-protect yet — dashboard default.
  emptyVault,

  /// No warranties match — items list empty/no-results.
  noWarranties,

  /// No claims filed yet — claims list.
  noClaims,

  /// No notifications — notifications list inbox-zero.
  noNotifications,

  /// No maintenance tasks due — maintenance screen all-clear.
  noMaintenance,

  /// No archived items — archived list empty.
  noArchive,

  /// No email scans yet — email scanner empty history.
  noScans,

  /// Search placeholder — global search before user types.
  searchIdle,
}

/// Branded empty-state illustration. Pair with a title + subtitle.
/// Defaults to a 160dp square, which is the right size for dashboard-scale
/// empty states without overwhelming the view.
class HavenIllustration extends StatelessWidget {
  final HavenIllustrationKind kind;
  final double size;

  const HavenIllustration({
    super.key,
    required this.kind,
    this.size = 160,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IllustrationPainter(kind),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _IllustrationPainter extends CustomPainter {
  final HavenIllustrationKind kind;

  _IllustrationPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _paintBackdrop(canvas, rect);

    switch (kind) {
      case HavenIllustrationKind.emptyVault:
        _paintVault(canvas, rect);
        break;
      case HavenIllustrationKind.noWarranties:
        _paintStackedCards(canvas, rect);
        break;
      case HavenIllustrationKind.noClaims:
        _paintReceipt(canvas, rect);
        break;
      case HavenIllustrationKind.noNotifications:
        _paintBell(canvas, rect);
        break;
      case HavenIllustrationKind.noMaintenance:
        _paintWrenchGear(canvas, rect);
        break;
      case HavenIllustrationKind.noArchive:
        _paintArchiveBox(canvas, rect);
        break;
      case HavenIllustrationKind.noScans:
        _paintEnvelope(canvas, rect);
        break;
      case HavenIllustrationKind.searchIdle:
        _paintMagnifier(canvas, rect);
        break;
    }
  }

  // Shared "halo" backdrop — a soft radial glow so the illustration reads
  // as an intentional hero element rather than an icon.
  void _paintBackdrop(Canvas canvas, Rect rect) {
    final center = rect.center;
    final radius = rect.shortestSide * 0.48;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          HavenColors.primary.withValues(alpha: 0.18),
          HavenColors.secondary.withValues(alpha: 0.06),
          HavenColors.background.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  // A reusable "chip" (rounded rectangle) so illustrations compose cleanly.
  void _drawChip(
    Canvas canvas,
    Rect bounds, {
    required Color color,
    double radius = 8,
    double borderWidth = 0,
    Color? borderColor,
  }) {
    final rrect = RRect.fromRectAndRadius(bounds, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = color);
    if (borderWidth > 0 && borderColor != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }
  }

  // ---- Individual illustrations ----

  void _paintVault(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;

    // Shield silhouette (primary gradient)
    final shieldPath = Path();
    final w = 88 * unit;
    final h = 100 * unit;
    shieldPath.moveTo(center.dx, center.dy - h / 2);
    shieldPath.quadraticBezierTo(
      center.dx + w / 2, center.dy - h / 2 + 8 * unit,
      center.dx + w / 2, center.dy - h / 4,
    );
    shieldPath.cubicTo(
      center.dx + w / 2, center.dy + h / 4,
      center.dx + w / 3, center.dy + h / 2 - 4 * unit,
      center.dx, center.dy + h / 2,
    );
    shieldPath.cubicTo(
      center.dx - w / 3, center.dy + h / 2 - 4 * unit,
      center.dx - w / 2, center.dy + h / 4,
      center.dx - w / 2, center.dy - h / 4,
    );
    shieldPath.quadraticBezierTo(
      center.dx - w / 2, center.dy - h / 2 + 8 * unit,
      center.dx, center.dy - h / 2,
    );
    shieldPath.close();

    canvas.drawPath(
      shieldPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HavenColors.primary,
            HavenColors.secondary,
          ],
        ).createShader(rect),
    );

    // Inner highlight
    canvas.drawPath(
      shieldPath,
      Paint()
        ..color = HavenColors.textPrimary.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * unit,
    );

    // Lock / keyhole
    final keyholeCenter = Offset(center.dx, center.dy - 4 * unit);
    canvas.drawCircle(
      keyholeCenter,
      10 * unit,
      Paint()..color = HavenColors.textPrimary.withValues(alpha: 0.9),
    );
    final stemRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 8 * unit),
      width: 6 * unit,
      height: 18 * unit,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(stemRect, Radius.circular(3 * unit)),
      Paint()..color = HavenColors.textPrimary.withValues(alpha: 0.9),
    );

    // Gold spark
    _drawSparkle(canvas, Offset(center.dx + 50 * unit, center.dy - 40 * unit),
        6 * unit, HavenColors.gold);
    _drawSparkle(canvas, Offset(center.dx - 46 * unit, center.dy + 30 * unit),
        4 * unit, HavenColors.gold.withValues(alpha: 0.7));
  }

  void _paintStackedCards(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;

    // Back card (tilted)
    canvas.save();
    canvas.translate(center.dx, center.dy + 2 * unit);
    canvas.rotate(-0.18);
    _drawChip(
      canvas,
      Rect.fromCenter(width: 100 * unit, height: 64 * unit, center: Offset.zero),
      color: HavenColors.elevated,
      radius: 10 * unit,
      borderWidth: 1.2 * unit,
      borderColor: HavenColors.border,
    );
    canvas.restore();

    // Mid card
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.06);
    _drawChip(
      canvas,
      Rect.fromCenter(width: 108 * unit, height: 66 * unit, center: Offset.zero),
      color: HavenColors.surface,
      radius: 12 * unit,
      borderWidth: 1.2 * unit,
      borderColor: HavenColors.border,
    );
    canvas.restore();

    // Front card (primary gradient)
    final frontRect = Rect.fromCenter(
        center: Offset(center.dx + 6 * unit, center.dy - 4 * unit),
        width: 112 * unit,
        height: 68 * unit);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frontRect, Radius.circular(12 * unit)),
      Paint()
        ..shader = const LinearGradient(
          colors: [HavenColors.primary, HavenColors.secondary],
        ).createShader(frontRect),
    );

    // Little shield badge on front
    final badgeCenter =
        Offset(frontRect.left + 14 * unit, frontRect.top + 14 * unit);
    canvas.drawCircle(
      badgeCenter,
      8 * unit,
      Paint()..color = HavenColors.textPrimary.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      badgeCenter,
      4 * unit,
      Paint()..color = HavenColors.gold,
    );

    // Two content lines
    _drawChip(
      canvas,
      Rect.fromLTWH(frontRect.left + 28 * unit, frontRect.top + 10 * unit,
          52 * unit, 6 * unit),
      color: HavenColors.textPrimary.withValues(alpha: 0.85),
      radius: 3 * unit,
    );
    _drawChip(
      canvas,
      Rect.fromLTWH(frontRect.left + 28 * unit, frontRect.top + 22 * unit,
          36 * unit, 4 * unit),
      color: HavenColors.textPrimary.withValues(alpha: 0.55),
      radius: 2 * unit,
    );
  }

  void _paintReceipt(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;
    final paperRect = Rect.fromCenter(
        center: center, width: 74 * unit, height: 100 * unit);

    // Zig-zag bottom path so it reads like a torn receipt
    final path = Path()
      ..moveTo(paperRect.left, paperRect.top)
      ..lineTo(paperRect.right, paperRect.top)
      ..lineTo(paperRect.right, paperRect.bottom - 6 * unit);
    // bottom zig-zag
    const teeth = 6;
    final toothW = paperRect.width / teeth;
    for (var i = 0; i < teeth; i++) {
      final x = paperRect.right - (i + 1) * toothW;
      final yOffset = i.isEven ? 6 * unit : 0.0;
      path.lineTo(x, paperRect.bottom - yOffset);
    }
    path.lineTo(paperRect.left, paperRect.bottom - 6 * unit);
    path.close();

    canvas.drawPath(
      path,
      Paint()..color = HavenColors.surface,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = HavenColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * unit,
    );

    // Header bar (primary accent)
    _drawChip(
      canvas,
      Rect.fromLTWH(paperRect.left + 10 * unit, paperRect.top + 10 * unit,
          paperRect.width - 20 * unit, 6 * unit),
      color: HavenColors.primary,
      radius: 3 * unit,
    );

    // Body lines
    for (var i = 0; i < 4; i++) {
      _drawChip(
        canvas,
        Rect.fromLTWH(
            paperRect.left + 10 * unit,
            paperRect.top + (24 + i * 12) * unit,
            paperRect.width - 20 * unit - (i == 3 ? 18 * unit : 0),
            4 * unit),
        color: HavenColors.textTertiary.withValues(alpha: 0.6),
        radius: 2 * unit,
      );
    }

    // Large checkmark stamp (gold) bottom-right
    final stampCenter = Offset(paperRect.right + 2 * unit, paperRect.bottom - 10 * unit);
    canvas.drawCircle(
      stampCenter,
      16 * unit,
      Paint()..color = HavenColors.gold.withValues(alpha: 0.15),
    );
    canvas.drawCircle(
      stampCenter,
      16 * unit,
      Paint()
        ..color = HavenColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * unit,
    );
    _drawCheckmark(canvas, stampCenter, 18 * unit, HavenColors.gold);
  }

  void _paintBell(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;

    // Bell body
    final bellTop = center.dy - 38 * unit;
    final bellBottom = center.dy + 24 * unit;
    final path = Path()
      ..moveTo(center.dx - 36 * unit, bellBottom)
      ..quadraticBezierTo(center.dx - 36 * unit, bellTop,
          center.dx, bellTop - 6 * unit)
      ..quadraticBezierTo(center.dx + 36 * unit, bellTop,
          center.dx + 36 * unit, bellBottom)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HavenColors.primary, HavenColors.secondary],
        ).createShader(rect),
    );

    // Bell clapper
    canvas.drawCircle(
      Offset(center.dx, bellBottom + 8 * unit),
      5 * unit,
      Paint()..color = HavenColors.textPrimary,
    );

    // Base rim
    _drawChip(
      canvas,
      Rect.fromCenter(
          center: Offset(center.dx, bellBottom),
          width: 80 * unit,
          height: 6 * unit),
      color: HavenColors.textPrimary.withValues(alpha: 0.9),
      radius: 3 * unit,
    );

    // "Zzz" floating — signals "quiet / inbox-zero"
    _drawZzz(canvas, Offset(center.dx + 44 * unit, center.dy - 32 * unit),
        unit * 1.2);
  }

  void _paintWrenchGear(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;

    // Gear
    final gearCenter = Offset(center.dx - 18 * unit, center.dy + 10 * unit);
    _drawGear(canvas, gearCenter, 28 * unit, 8, HavenColors.secondary);
    canvas.drawCircle(
      gearCenter,
      10 * unit,
      Paint()..color = HavenColors.background,
    );

    // Wrench overlapping
    canvas.save();
    canvas.translate(center.dx + 16 * unit, center.dy - 18 * unit);
    canvas.rotate(-math.pi / 4);
    // Handle
    _drawChip(
      canvas,
      Rect.fromCenter(
          center: Offset.zero, width: 10 * unit, height: 70 * unit),
      color: HavenColors.primary,
      radius: 4 * unit,
    );
    // Jaw
    final jawCenter = Offset(0, -38 * unit);
    canvas.drawCircle(
      jawCenter,
      13 * unit,
      Paint()..color = HavenColors.primary,
    );
    canvas.drawCircle(
      jawCenter,
      6 * unit,
      Paint()..color = HavenColors.background,
    );
    canvas.restore();
  }

  void _paintArchiveBox(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;

    // Box base
    final baseRect = Rect.fromCenter(
        center: Offset(center.dx, center.dy + 14 * unit),
        width: 96 * unit,
        height: 56 * unit);
    _drawChip(
      canvas,
      baseRect,
      color: HavenColors.surface,
      radius: 6 * unit,
      borderWidth: 1.4 * unit,
      borderColor: HavenColors.border,
    );

    // Lid
    final lidRect = Rect.fromCenter(
        center: Offset(center.dx, center.dy - 18 * unit),
        width: 104 * unit,
        height: 22 * unit);
    _drawChip(
      canvas,
      lidRect,
      color: HavenColors.elevated,
      radius: 6 * unit,
      borderWidth: 1.4 * unit,
      borderColor: HavenColors.border,
    );

    // Handle slot
    _drawChip(
      canvas,
      Rect.fromCenter(
          center: Offset(center.dx, center.dy - 18 * unit),
          width: 28 * unit,
          height: 4 * unit),
      color: HavenColors.primary.withValues(alpha: 0.9),
      radius: 2 * unit,
    );

    // Curved "restore" arrow sweeping up over the box
    final arrowCenter = Offset(center.dx + 36 * unit, center.dy - 20 * unit);
    final arrowPaint = Paint()
      ..color = HavenColors.active
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * unit
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: arrowCenter, radius: 16 * unit),
      -math.pi * 0.2,
      -math.pi * 1.1,
      false,
      arrowPaint,
    );
    // Arrowhead
    final headPath = Path()
      ..moveTo(arrowCenter.dx - 16 * unit, arrowCenter.dy - 2 * unit)
      ..lineTo(arrowCenter.dx - 10 * unit, arrowCenter.dy - 10 * unit)
      ..lineTo(arrowCenter.dx - 20 * unit, arrowCenter.dy - 8 * unit)
      ..close();
    canvas.drawPath(headPath, Paint()..color = HavenColors.active);
  }

  void _paintEnvelope(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;

    final envRect = Rect.fromCenter(
        center: center, width: 104 * unit, height: 72 * unit);
    _drawChip(
      canvas,
      envRect,
      color: HavenColors.surface,
      radius: 6 * unit,
      borderWidth: 1.4 * unit,
      borderColor: HavenColors.border,
    );

    // Flap
    final flapPath = Path()
      ..moveTo(envRect.left, envRect.top)
      ..lineTo(envRect.center.dx, envRect.center.dy)
      ..lineTo(envRect.right, envRect.top)
      ..close();
    canvas.drawPath(
      flapPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [HavenColors.primary, HavenColors.secondary],
        ).createShader(flapPath.getBounds()),
    );

    // Sparkle (scan) — top-right
    _drawSparkle(canvas, Offset(envRect.right + 4 * unit, envRect.top - 2 * unit),
        8 * unit, HavenColors.gold);
    _drawSparkle(canvas, Offset(envRect.right + 18 * unit, envRect.top + 14 * unit),
        5 * unit, HavenColors.gold.withValues(alpha: 0.7));
  }

  void _paintMagnifier(Canvas canvas, Rect rect) {
    final unit = rect.width / 160;
    final center = rect.center;

    final lensCenter =
        Offset(center.dx - 6 * unit, center.dy - 6 * unit);
    final lensRadius = 28 * unit;

    // Lens (primary gradient ring)
    canvas.drawCircle(
      lensCenter,
      lensRadius,
      Paint()
        ..shader = const LinearGradient(
          colors: [HavenColors.primary, HavenColors.secondary],
        ).createShader(Rect.fromCircle(center: lensCenter, radius: lensRadius)),
    );
    canvas.drawCircle(
      lensCenter,
      lensRadius - 6 * unit,
      Paint()..color = HavenColors.background,
    );

    // Handle
    canvas.save();
    canvas.translate(lensCenter.dx + lensRadius * 0.7,
        lensCenter.dy + lensRadius * 0.7);
    canvas.rotate(math.pi / 4);
    _drawChip(
      canvas,
      Rect.fromCenter(
          center: Offset(0, 18 * unit), width: 10 * unit, height: 44 * unit),
      color: HavenColors.primary,
      radius: 4 * unit,
    );
    canvas.restore();

    // Inner sparkle
    _drawSparkle(canvas, lensCenter, 6 * unit, HavenColors.gold);
  }

  // ---- Low-level helpers ----

  void _drawSparkle(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(center.dx, center.dy - size);
    path.lineTo(center.dx + size * 0.3, center.dy - size * 0.3);
    path.lineTo(center.dx + size, center.dy);
    path.lineTo(center.dx + size * 0.3, center.dy + size * 0.3);
    path.lineTo(center.dx, center.dy + size);
    path.lineTo(center.dx - size * 0.3, center.dy + size * 0.3);
    path.lineTo(center.dx - size, center.dy);
    path.lineTo(center.dx - size * 0.3, center.dy - size * 0.3);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawCheckmark(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(center.dx - size * 0.28, center.dy)
      ..lineTo(center.dx - size * 0.05, center.dy + size * 0.22)
      ..lineTo(center.dx + size * 0.28, center.dy - size * 0.22);
    canvas.drawPath(path, paint);
  }

  void _drawZzz(Canvas canvas, Offset origin, double unit) {
    final style = TextStyle(
      color: HavenColors.textSecondary,
      fontSize: 16 * unit,
      fontWeight: FontWeight.w700,
      height: 1.0,
    );
    for (var i = 0; i < 3; i++) {
      final tp = TextPainter(
        text: TextSpan(text: 'z', style: style.copyWith(
          fontSize: (16 - i * 3) * unit,
          color: HavenColors.textSecondary
              .withValues(alpha: 0.4 + i * 0.18),
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, origin.translate(-i * 10 * unit, -i * 12 * unit));
    }
  }

  void _drawGear(Canvas canvas, Offset center, double radius, int teeth,
      Color color) {
    final paint = Paint()..color = color;
    final path = Path();
    const innerScale = 0.78;
    const toothScale = 1.1;
    for (var i = 0; i < teeth * 2; i++) {
      final angle = (i / (teeth * 2)) * math.pi * 2;
      final r = i.isEven ? radius * toothScale : radius * innerScale;
      final p = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter old) => old.kind != kind;
}
