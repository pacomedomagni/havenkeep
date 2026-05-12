import 'package:flutter/material.dart';

import 'theme.dart';

/// Visual weight of a [HavenCard].
enum HavenCardVariant {
  /// Resting card on the page canvas — [HavenColors.surface], soft ambient
  /// shadow, hairline outline + top highlight. The default.
  surface,

  /// A card that sits on top of another surface — one tier lighter, a
  /// slightly deeper shadow. Use for nested cards (a card inside a card),
  /// or for the "hero" card on a screen.
  elevated,

  /// A flush panel with no shadow — for grouped rows that live directly on
  /// the canvas (search fields, settings groups). Just the hairline
  /// outline; reads as inset rather than lifted.
  flat,

  /// A highlighted / featured surface — gradient fill in the brand accents
  /// with a stronger glow. Use sparingly: the dashboard value card, the
  /// premium teaser, milestone banners.
  highlight,
}

/// The single card primitive for HavenKeep. Replaces the dozens of
/// hand-rolled `Container(decoration: BoxDecoration(...))` blocks and the
/// bare `GestureDetector` cards that gave no touch feedback.
///
/// When [onTap] is non-null the card is a real button: it gets the branded
/// ink ripple, a keyboard / D-pad focus ring, a `Semantics(button:true)`
/// wrapper, and a subtle press-scale (the whole card dips ~2% on touch-down
/// and springs back). Pass [glow] for a soft colored halo behind the card —
/// reserve that for hero / featured surfaces.
///
/// ```dart
/// HavenCard(onTap: ..., child: Row(children: [...]))
/// HavenCard.elevated(child: ...)            // hero card
/// HavenCard.flat(padding: EdgeInsets.zero, child: searchField)
/// HavenCard.highlight(glow: HavenColors.accent, child: valueDashboard)
/// ```
class HavenCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HavenCardVariant variant;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final double? width;

  /// Override the gradient used by [HavenCardVariant.highlight] (ignored by
  /// the other variants). Defaults to indigo → violet accent.
  final Gradient? gradient;

  /// Override the outline color. Defaults per-variant.
  final Color? borderColor;

  /// Soft colored halo behind the card (via [HavenElevation.glow]). Null =
  /// no glow. Use only on hero / featured surfaces.
  final Color? glow;

  /// Whether a tappable card does the press-scale dip. On by default; turn
  /// it off for tiny rows where the dip looks twitchy.
  final bool pressEffect;

  /// For [Semantics] — describes the card to screen readers when it's
  /// tappable. If null and [onTap] is set, the child's own semantics are
  /// used.
  final String? semanticLabel;

  const HavenCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.variant = HavenCardVariant.surface,
    this.padding,
    this.margin,
    this.radius,
    this.width,
    this.gradient,
    this.borderColor,
    this.glow,
    this.pressEffect = true,
    this.semanticLabel,
  });

  const HavenCard.elevated({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.radius,
    this.width,
    this.borderColor,
    this.glow,
    this.pressEffect = true,
    this.semanticLabel,
  })  : variant = HavenCardVariant.elevated,
        gradient = null;

  const HavenCard.flat({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.radius,
    this.width,
    this.borderColor,
    this.pressEffect = true,
    this.semanticLabel,
  })  : variant = HavenCardVariant.flat,
        gradient = null,
        glow = null;

  const HavenCard.highlight({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.radius,
    this.width,
    this.gradient,
    this.borderColor,
    this.glow,
    this.pressEffect = true,
    this.semanticLabel,
  }) : variant = HavenCardVariant.highlight;

  @override
  State<HavenCard> createState() => _HavenCardState();
}

class _HavenCardState extends State<HavenCard> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;
  bool get _animatePress => _interactive && widget.pressEffect;

  @override
  Widget build(BuildContext context) {
    final r = widget.radius ?? HavenRadius.card;
    final borderRadius = BorderRadius.circular(r);
    final pad = widget.padding ?? const EdgeInsets.all(HavenSpacing.md);

    final isHighlight = widget.variant == HavenCardVariant.highlight;
    final isFlat = widget.variant == HavenCardVariant.flat;

    final Color baseColor = switch (widget.variant) {
      HavenCardVariant.surface => HavenColors.surface,
      HavenCardVariant.elevated => HavenColors.surfaceElevated,
      HavenCardVariant.flat => HavenColors.surface,
      HavenCardVariant.highlight => HavenColors.accent,
    };
    final List<BoxShadow> ambient = switch (widget.variant) {
      HavenCardVariant.surface => HavenElevation.shadowFor(1),
      HavenCardVariant.elevated => HavenElevation.shadowFor(2),
      HavenCardVariant.flat => const [],
      HavenCardVariant.highlight => [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
    };
    final shadows = <BoxShadow>[
      if (widget.glow != null) ...HavenElevation.glow(widget.glow!),
      ...ambient,
    ];
    final Color outline = widget.borderColor ??
        (isHighlight
            ? Colors.white.withValues(alpha: 0.16)
            : HavenColors.border);

    final decoration = BoxDecoration(
      color: isHighlight ? null : baseColor,
      gradient: isHighlight ? (widget.gradient ?? HavenGradients.brandSoft) : null,
      borderRadius: borderRadius,
      border: Border.all(color: outline, width: 1),
      boxShadow: shadows,
    );

    final foregroundSheen = (isFlat || isHighlight)
        ? null
        : BoxDecoration(
            borderRadius: borderRadius,
            gradient: HavenElevation.sheen(
              strength: widget.variant == HavenCardVariant.elevated ? 1.2 : 1,
            ),
          );

    Widget content = DecoratedBox(
      decoration: decoration,
      child: foregroundSheen != null
          ? DecoratedBox(
              decoration: foregroundSheen,
              child: _maybeInk(borderRadius, pad),
            )
          : _maybeInk(borderRadius, pad),
    );

    if (_animatePress) {
      content = AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: HavenMotion.fast,
        curve: Curves.easeOut,
        child: content,
      );
    }

    if (widget.width != null) {
      content = SizedBox(width: widget.width, child: content);
    }
    if (widget.margin != null) {
      content = Padding(padding: widget.margin!, child: content);
    }
    return content;
  }

  Widget _maybeInk(BorderRadius borderRadius, EdgeInsetsGeometry pad) {
    final padded = Padding(padding: pad, child: widget.child);
    if (!_interactive) {
      return ClipRRect(borderRadius: borderRadius, child: padded);
    }
    final isHighlight = widget.variant == HavenCardVariant.highlight;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: _animatePress
              ? (v) {
                  if (mounted) setState(() => _pressed = v);
                }
              : null,
          borderRadius: borderRadius,
          splashColor: isHighlight
              ? Colors.white.withValues(alpha: 0.16)
              : null,
          highlightColor: isHighlight
              ? Colors.white.withValues(alpha: 0.06)
              : null,
          child: widget.semanticLabel != null
              ? Semantics(button: true, label: widget.semanticLabel, child: padded)
              : padded,
        ),
      ),
    );
  }
}
