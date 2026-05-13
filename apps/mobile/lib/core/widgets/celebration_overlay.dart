import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Dignified celebration moment shown as a transient overlay. Uses
/// [HavenSuccessFlourish] for the visual flourish (gold sweep + glyph)
/// instead of confetti. Auto-dismisses after 2.5 seconds; tap anywhere
/// to dismiss sooner.
///
/// This is the "transient overlay" celebration — for the persistent
/// success surface (a full screen with a primary CTA), build the screen
/// directly with [HavenSuccessFlourish].
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

  /// Shows the celebration overlay above the current route.
  static void show(
    BuildContext context, {
    required CelebrationType type,
    required String title,
    required String subtitle,
    VoidCallback? onDismiss,
  }) {
    var isOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: HavenColors.canvas.withValues(alpha: 0.72),
      builder: (context) => CelebrationOverlay(
        type: type,
        title: title,
        subtitle: subtitle,
        onDismiss: onDismiss,
      ),
    ).then((_) {
      isOpen = false;
    });

    // Auto-dismiss after 2.5s. Long enough to read the message, short
    // enough that it doesn't feel like a wait.
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (context.mounted && isOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        onDismiss?.call();
      }
    });
  }

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: HavenMotion.medium,
      vsync: this,
    )..forward();
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _iconFor(CelebrationType type) => switch (type) {
        CelebrationType.firstItem => Icons.check_rounded,
        CelebrationType.itemAdded => Icons.check_rounded,
        CelebrationType.receiptScanned => Icons.receipt_long_rounded,
        CelebrationType.milestone => Icons.emoji_events_rounded,
        CelebrationType.allWarrantiesActive => Icons.verified_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        widget.onDismiss?.call();
      },
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.xl),
                child: HavenCard.elevated(
                  glow: HavenColors.gold,
                  padding: const EdgeInsets.fromLTRB(
                    HavenSpacing.xl,
                    HavenSpacing.xl,
                    HavenSpacing.xl,
                    HavenSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HavenSuccessFlourish(icon: _iconFor(widget.type)),
                      const SizedBox(height: HavenSpacing.md),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: HavenText.displayMedium,
                      ),
                      const SizedBox(height: HavenSpacing.xs),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: HavenText.bodySecondary,
                      ),
                      const SizedBox(height: HavenSpacing.md),
                      const Text(
                        'Tap anywhere to continue',
                        style: HavenText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Types of celebrations. Kept stable so existing callers keep working
/// after the visual rewrite.
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
    if (previousCount == 0 && newCount == 1) {
      return CelebrationType.firstItem;
    }
    if (_isMilestone(newCount) && !_isMilestone(previousCount)) {
      return CelebrationType.milestone;
    }
    return CelebrationType.itemAdded;
  }

  static bool _isMilestone(int count) {
    return count == 5 ||
        count == 10 ||
        count == 25 ||
        count == 50 ||
        count == 100;
  }

  /// Gets celebration message based on type and count.
  static (String title, String subtitle) getMessage(
    CelebrationType type,
    int itemCount,
  ) {
    switch (type) {
      case CelebrationType.firstItem:
        return (
          'Great start',
          'Your first item is protected. Keep adding to build your warranty vault.'
        );
      case CelebrationType.milestone:
        return (
          '$itemCount items protected',
          "You're building an impressive warranty collection. Keep it up!"
        );
      case CelebrationType.itemAdded:
        return (
          'Item added',
          'Your warranty is now tracked and protected.'
        );
      case CelebrationType.receiptScanned:
        return (
          'Receipt scanned',
          "We've extracted the details automatically. Review and save."
        );
      case CelebrationType.allWarrantiesActive:
        return (
          '100% warranty health',
          'All your items have active warranties. Excellent management.'
        );
    }
  }
}
