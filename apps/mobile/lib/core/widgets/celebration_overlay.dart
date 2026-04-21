import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/utils/haven_haptics.dart';

/// Shows celebration animations when users accomplish goals.
class CelebrationOverlay extends StatefulWidget {
  final CelebrationType type;
  final String title;
  final String subtitle;
  final VoidCallback? onDismiss;

  const CelebrationOverlay({
    super.key,
    required this.type,
    required this.title,
    required this.subtitle,
    this.onDismiss,
  });

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();

  /// Shows the celebration overlay.
  static void show(
    BuildContext context, {
    required CelebrationType type,
    required String title,
    required String subtitle,
    VoidCallback? onDismiss,
  }) {
    HavenHaptics.celebrate();

    var isOpen = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: HavenColors.background.withValues(alpha: 0.6),
      builder: (context) => CelebrationOverlay(
        type: type,
        title: title,
        subtitle: subtitle,
        onDismiss: onDismiss,
      ),
    ).then((_) {
      isOpen = false;
    });

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (context.mounted && isOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        onDismiss?.call();
      }
    });
  }
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    _confetti =
        ConfettiController(duration: const Duration(milliseconds: 1200));
    if (widget.type == CelebrationType.firstItem ||
        widget.type == CelebrationType.milestone) {
      _confetti.play();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        widget.onDismiss?.call();
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Confetti burst from the top center
            if (widget.type == CelebrationType.firstItem ||
                widget.type == CelebrationType.milestone)
              Align(
                alignment: Alignment.topCenter,
                child: IgnorePointer(
                  child: ConfettiWidget(
                    confettiController: _confetti,
                    blastDirection: math.pi / 2,
                    emissionFrequency: 0.04,
                    numberOfParticles: 22,
                    gravity: 0.35,
                    maxBlastForce: 18,
                    minBlastForce: 8,
                    colors: const [
                      HavenColors.primary,
                      HavenColors.secondary,
                      HavenColors.gold,
                      HavenColors.active,
                    ],
                  ),
                ),
              ),

            // Success card
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: HavenColors.textPrimary,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: HavenColors.background.withValues(alpha: 0.2),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon/Animation
                        _buildIcon(),

                        const SizedBox(height: 24),

                        // Title
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: HavenColors.background,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Subtitle
                        Text(
                          widget.subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: HavenColors.textSecondary,
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Tap to dismiss hint
                        const Text(
                          'Tap anywhere to continue',
                          style: TextStyle(
                            fontSize: 13,
                            color: HavenColors.textTertiary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (widget.type) {
      case CelebrationType.firstItem:
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: HavenColors.active.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: AnimatedCheckmark(
              size: 72,
              color: HavenColors.active,
            ),
          ),
        );

      case CelebrationType.milestone:
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                HavenColors.accent.withValues(alpha: 0.2),
                HavenColors.accentSecondary.withValues(alpha: 0.2),
              ],
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.emoji_events,
            size: 64,
            color: HavenColors.accent,
          ),
        );

      case CelebrationType.itemAdded:
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: HavenColors.accent.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            size: 56,
            color: HavenColors.accent,
          ),
        );

      case CelebrationType.receiptScanned:
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: HavenColors.accentSecondary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.receipt_long,
            size: 56,
            color: HavenColors.accentSecondary,
          ),
        );

      case CelebrationType.allWarrantiesActive:
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: HavenColors.active.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.verified_user,
            size: 64,
            color: HavenColors.active,
          ),
        );
    }
  }
}

/// Types of celebrations.
enum CelebrationType {
  /// First item added to the vault.
  firstItem,

  /// Regular item added (not first).
  itemAdded,

  /// Receipt successfully scanned.
  receiptScanned,

  /// Milestone reached (5, 10, 25, 50, 100 items).
  milestone,

  /// All warranties are active (100% health).
  allWarrantiesActive,
}

/// Helper class to determine when to celebrate.
class CelebrationTrigger {
  /// Checks if we should celebrate based on item count.
  static CelebrationType? checkItemAdded(int previousCount, int newCount) {
    // First item is special
    if (previousCount == 0 && newCount == 1) {
      return CelebrationType.firstItem;
    }

    // Milestones: 5, 10, 25, 50, 100
    if (_isMilestone(newCount) && !_isMilestone(previousCount)) {
      return CelebrationType.milestone;
    }

    // Regular add
    return CelebrationType.itemAdded;
  }

  static bool _isMilestone(int count) {
    return count == 5 || count == 10 || count == 25 || count == 50 || count == 100;
  }

  /// Gets celebration message based on type and count.
  static (String title, String subtitle) getMessage(
    CelebrationType type,
    int itemCount,
  ) {
    switch (type) {
      case CelebrationType.firstItem:
        return (
          '🎉 Great start!',
          'Your first item is protected. Keep adding to build your warranty vault.'
        );

      case CelebrationType.milestone:
        return (
          '🏆 $itemCount Items Protected!',
          "You're building an impressive warranty collection. Keep it up!"
        );

      case CelebrationType.itemAdded:
        return (
          'Item Added!',
          'Your warranty is now tracked and protected.'
        );

      case CelebrationType.receiptScanned:
        return (
          'Receipt Scanned!',
          "We've extracted the details automatically. Review and save."
        );

      case CelebrationType.allWarrantiesActive:
        return (
          '100% Warranty Health!',
          'All your items have active warranties. Excellent management!'
        );
    }
  }
}

/// Native (Lottie-free) success checkmark that draws its stroke in and
/// then scales with a little overshoot. Use as the hero glyph for any
/// success moment — faster than loading an asset, branded by color.
class AnimatedCheckmark extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const AnimatedCheckmark({
    super.key,
    this.size = 64,
    this.color = HavenColors.active,
    this.duration = const Duration(milliseconds: 720),
  });

  @override
  State<AnimatedCheckmark> createState() => _AnimatedCheckmarkState();
}

class _AnimatedCheckmarkState extends State<AnimatedCheckmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CheckmarkPainter(
          progress: Curves.easeOutCubic.transform(_c.value),
          color: widget.color,
        ),
      ),
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.12;

    // Checkmark points, normalized to the box.
    final p1 = Offset(size.width * 0.22, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.72);
    final p3 = Offset(size.width * 0.78, size.height * 0.32);

    final path = Path()..moveTo(p1.dx, p1.dy);
    // Split progress across two segments proportional to their length.
    final seg1Length = (p2 - p1).distance;
    final seg2Length = (p3 - p2).distance;
    final total = seg1Length + seg2Length;
    final cutoff = seg1Length / total;

    if (progress <= cutoff) {
      final t = progress / cutoff;
      final end = Offset.lerp(p1, p2, t)!;
      path.lineTo(end.dx, end.dy);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final t = (progress - cutoff) / (1 - cutoff);
      final end = Offset.lerp(p2, p3, t)!;
      path.lineTo(end.dx, end.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter old) =>
      old.progress != progress || old.color != color;
}
