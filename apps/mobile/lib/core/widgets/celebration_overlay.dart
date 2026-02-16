import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_ui/shared_ui.dart';

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
    HapticFeedback.heavyImpact();

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
  }

  @override
  void dispose() {
    _controller.dispose();
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
            // Confetti animation (full screen)
            if (widget.type == CelebrationType.firstItem ||
                widget.type == CelebrationType.milestone)
              Positioned.fill(
                child: IgnorePointer(
                  child: Lottie.asset(
                    'assets/lottie/confetti_celebration.json',
                    repeat: false,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
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
                          style: TextStyle(
                            fontSize: 16,
                            color: HavenColors.textSecondary,
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Tap to dismiss hint
                        Text(
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
          child: Lottie.asset(
            'assets/lottie/success_checkmark.json',
            width: 80,
            height: 80,
            repeat: false,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.check_circle,
                size: 80,
                color: HavenColors.active,
              );
            },
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
          '🏆 ${itemCount} Items Protected!',
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
