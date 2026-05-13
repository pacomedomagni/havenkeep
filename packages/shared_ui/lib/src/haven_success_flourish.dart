import 'package:flutter/material.dart';

import 'haven_haptics.dart';
import 'theme.dart';

/// A dignified celebration moment — no confetti, no Lottie. A gold-tinted
/// disc with a checkmark draws in over ~640ms; a soft halo sweeps out
/// behind it; a heavy haptic fires once at the start. Use this on the
/// success surface for the five wins that matter:
///
///   * Item added
///   * Claim filed
///   * Gift activated
///   * Premium upgrade
///   * (Optional) maintenance task marked done — inline variant
///
/// Calibrated against the Cron / Notion Calendar visual language: this is
/// the kind of celebration software craftsmen ship. The point is that the
/// user *notices* but is never embarrassed.
///
/// ```dart
/// HavenSuccessFlourish(
///   icon: Icons.check_rounded,
///   size: 96,
/// )
/// ```
class HavenSuccessFlourish extends StatefulWidget {
  /// The icon drawn in after the disc lands. Defaults to a check.
  final IconData icon;

  /// Overall diameter of the disc. The halo extends ~40% beyond.
  final double size;

  /// Override the celebration tint. Defaults to [HavenColors.gold].
  final Color tint;

  /// Fire a haptic when the animation starts. On by default — opt out for
  /// the inline variant where the parent already fired one.
  final bool haptic;

  /// Replay the animation when this key changes. Without this, the
  /// celebration only plays once on first build.
  final Object? replayKey;

  const HavenSuccessFlourish({
    super.key,
    this.icon = Icons.check_rounded,
    this.size = 96,
    this.tint = HavenColors.gold,
    this.haptic = true,
    this.replayKey,
  });

  @override
  State<HavenSuccessFlourish> createState() => _HavenSuccessFlourishState();
}

class _HavenSuccessFlourishState extends State<HavenSuccessFlourish>
    with TickerProviderStateMixin {
  late AnimationController _disc;
  late AnimationController _glyph;
  late AnimationController _halo;

  late Animation<double> _discScale;
  late Animation<double> _discFade;
  late Animation<double> _glyphProgress;
  late Animation<double> _haloScale;
  late Animation<double> _haloFade;

  @override
  void initState() {
    super.initState();
    _disc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _glyph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    );

    _discScale = CurvedAnimation(
      parent: _disc,
      curve: Curves.easeOutBack,
    );
    _discFade = CurvedAnimation(parent: _disc, curve: Curves.easeOut);
    _glyphProgress = CurvedAnimation(parent: _glyph, curve: Curves.easeOut);
    _haloScale = Tween<double>(begin: 0.6, end: 1.4).animate(
      CurvedAnimation(parent: _halo, curve: Curves.easeOutCubic),
    );
    _haloFade = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(parent: _halo, curve: Curves.easeOut),
    );

    _play();
  }

  @override
  void didUpdateWidget(covariant HavenSuccessFlourish oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replayKey != null && widget.replayKey != oldWidget.replayKey) {
      _play();
    }
  }

  Future<void> _play() async {
    if (widget.haptic) HavenHaptics.celebrate();
    _disc.forward(from: 0);
    _halo.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    _glyph.forward(from: 0);
  }

  @override
  void dispose() {
    _disc.dispose();
    _glyph.dispose();
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.6,
      height: widget.size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo sweep
          AnimatedBuilder(
            animation: _halo,
            builder: (context, _) => Opacity(
              opacity: _haloFade.value,
              child: Transform.scale(
                scale: _haloScale.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.tint.withValues(alpha: 0.6),
                        widget.tint.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Disc + glyph
          AnimatedBuilder(
            animation: Listenable.merge([_disc, _glyph]),
            builder: (context, _) => Opacity(
              opacity: _discFade.value,
              child: Transform.scale(
                scale: 0.6 + (_discScale.value * 0.4),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.tint,
                        Color.lerp(
                              widget.tint,
                              const Color(0xFFB78900),
                              0.5,
                            ) ??
                            widget.tint,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.tint.withValues(alpha: 0.4),
                        blurRadius: 32,
                        spreadRadius: -2,
                        offset: const Offset(0, 12),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Opacity(
                      opacity: _glyphProgress.value,
                      child: Icon(
                        widget.icon,
                        size: widget.size * 0.42,
                        color: const Color(0xFF1A1505),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
