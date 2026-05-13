import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Visual weight of a [HavenButton].
enum HavenButtonVariant {
  /// Filled brand button — the primary call-to-action on a screen.
  /// Use at most once per surface (the "Add", "Save", "Continue" CTA).
  primary,

  /// Outlined button on the canvas — strong but secondary. Use for
  /// alternative actions next to a primary CTA ("Cancel", "Back").
  secondary,

  /// Quiet text button — minimal visual weight, just an inline action
  /// ("Edit", "Resend", "Skip"). No fill, no outline.
  tertiary,

  /// Destructive filled — red fill. Reserve for irreversible actions
  /// ("Delete", "Erase data"). Don't use for "Cancel".
  destructive,

  /// Ghost outlined — same shape as [secondary] but lower contrast.
  /// Use inside a card whose own outline already gives shape.
  ghost,
}

/// Size scale for a [HavenButton].
enum HavenButtonSize {
  /// 32px tall — chips and inline actions.
  sm,

  /// 44px tall — the default, matches iOS HIG touch target.
  md,

  /// 52px tall — full-width primary CTAs at the bottom of a screen.
  lg,
}

/// The single button primitive for HavenKeep. Replaces every
/// `ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton` and
/// hand-rolled `GestureDetector + Container` button across the app.
///
/// One widget, two enums. Variants control color + visual weight; sizes
/// control height + padding. Built-in:
///   * Branded press feedback (subtle scale dip + ink ripple).
///   * Haptic tick on press — automatic, calibrated per variant
///     (destructive uses a heavier haptic).
///   * Loading state: pass [isLoading]; the label is replaced by a spinner
///     and the button is disabled until you flip it back.
///   * Leading and trailing icon slots, sized off the icon scale.
///   * Full-width via [expand: true] for bottom-of-screen CTAs.
///
/// ```dart
/// HavenButton.primary(
///   label: 'Save changes',
///   onPressed: _save,
///   isLoading: _saving,
///   expand: true,
/// )
/// HavenButton.tertiary(label: 'Skip', leadingIcon: Icons.skip_next, ...)
/// HavenButton.destructive(label: 'Delete', onPressed: _confirm)
/// ```
class HavenButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final HavenButtonVariant variant;
  final HavenButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  /// While true, the label is swapped for a spinner and [onPressed] is
  /// ignored. Don't bind this to a local state without also resetting it
  /// when the async work completes — a stuck spinner is its own bug.
  final bool isLoading;

  /// Stretch to fill available width. Use for bottom-of-screen primary
  /// CTAs; leave false for inline buttons in a row.
  final bool expand;

  /// Override the `Semantics(button: true, label: ...)` value.
  /// Defaults to [label].
  final String? semanticLabel;

  const HavenButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = HavenButtonVariant.primary,
    this.size = HavenButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
  });

  const HavenButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = HavenButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = HavenButtonVariant.primary;

  const HavenButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = HavenButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = HavenButtonVariant.secondary;

  const HavenButton.tertiary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = HavenButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = HavenButtonVariant.tertiary;

  const HavenButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.size = HavenButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = HavenButtonVariant.destructive;

  const HavenButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.size = HavenButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = HavenButtonVariant.ghost;

  @override
  State<HavenButton> createState() => _HavenButtonState();
}

class _HavenButtonState extends State<HavenButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final geom = _geometryFor(widget.size);
    final colors = _colorsFor(widget.variant, _enabled);
    final radius = BorderRadius.circular(HavenRadius.button);

    final iconSize = widget.size == HavenButtonSize.sm
        ? HavenIconSize.micro
        : HavenIconSize.compact;

    final labelStyle = _labelStyleFor(widget.size).copyWith(color: colors.fg);

    final spinner = SizedBox(
      width: iconSize,
      height: iconSize,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(colors.fg),
      ),
    );

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading)
          spinner
        else if (widget.leadingIcon != null) ...[
          Icon(widget.leadingIcon, size: iconSize, color: colors.fg),
          const SizedBox(width: 8),
        ],
        if (!widget.isLoading) ...[
          Flexible(
            child: Text(
              widget.label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.trailingIcon != null) ...[
            const SizedBox(width: 8),
            Icon(widget.trailingIcon, size: iconSize, color: colors.fg),
          ],
        ],
      ],
    );

    final decoration = BoxDecoration(
      color: colors.bg,
      borderRadius: radius,
      border: colors.border != null
          ? Border.all(color: colors.border!, width: 1)
          : null,
      boxShadow: colors.glow != null && _enabled
          ? HavenElevation.glow(colors.glow!, strength: 0.7)
          : null,
    );

    Widget button = AnimatedContainer(
      duration: HavenMotion.fast,
      curve: Curves.easeOut,
      height: geom.height,
      constraints: BoxConstraints(minWidth: geom.minWidth),
      padding: geom.padding,
      decoration: decoration,
      child: Center(child: content),
    );

    button = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: HavenMotion.fast,
      curve: Curves.easeOut,
      child: button,
    );

    button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _enabled ? _handleTap : null,
        onHighlightChanged: (v) {
          if (mounted) setState(() => _pressed = v && _enabled);
        },
        borderRadius: radius,
        splashColor: colors.splash,
        highlightColor: colors.highlight,
        child: Semantics(
          button: true,
          enabled: _enabled,
          label: widget.semanticLabel ?? widget.label,
          child: button,
        ),
      ),
    );

    if (widget.expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  void _handleTap() {
    switch (widget.variant) {
      case HavenButtonVariant.destructive:
        HapticFeedback.mediumImpact();
      case HavenButtonVariant.primary:
        HapticFeedback.selectionClick();
      case HavenButtonVariant.secondary:
      case HavenButtonVariant.tertiary:
      case HavenButtonVariant.ghost:
        HapticFeedback.selectionClick();
    }
    widget.onPressed!();
  }
}

class _ButtonGeometry {
  final double height;
  final double minWidth;
  final EdgeInsetsGeometry padding;
  const _ButtonGeometry(this.height, this.minWidth, this.padding);
}

_ButtonGeometry _geometryFor(HavenButtonSize size) => switch (size) {
      HavenButtonSize.sm => const _ButtonGeometry(
          32,
          72,
          EdgeInsets.symmetric(horizontal: HavenSpacing.md),
        ),
      HavenButtonSize.md => const _ButtonGeometry(
          44,
          88,
          EdgeInsets.symmetric(horizontal: HavenSpacing.lg),
        ),
      HavenButtonSize.lg => const _ButtonGeometry(
          52,
          96,
          EdgeInsets.symmetric(horizontal: HavenSpacing.lg),
        ),
    };

TextStyle _labelStyleFor(HavenButtonSize size) => switch (size) {
      HavenButtonSize.sm => const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      HavenButtonSize.md => const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      HavenButtonSize.lg => const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
    };

class _ButtonColors {
  final Color bg;
  final Color fg;
  final Color? border;
  final Color? glow;
  final Color? splash;
  final Color? highlight;
  const _ButtonColors({
    required this.bg,
    required this.fg,
    this.border,
    this.glow,
    this.splash,
    this.highlight,
  });
}

_ButtonColors _colorsFor(HavenButtonVariant variant, bool enabled) {
  if (!enabled) {
    return const _ButtonColors(
      bg: HavenColors.surface,
      fg: HavenColors.textTertiary,
      border: HavenColors.borderHairline,
    );
  }
  return switch (variant) {
    HavenButtonVariant.primary => _ButtonColors(
        bg: HavenColors.primary,
        fg: HavenColors.textPrimary,
        glow: HavenColors.primary,
        splash: Colors.white.withValues(alpha: 0.18),
        highlight: Colors.white.withValues(alpha: 0.08),
      ),
    HavenButtonVariant.secondary => _ButtonColors(
        bg: HavenColors.surface,
        fg: HavenColors.textPrimary,
        border: HavenColors.border,
        splash: HavenColors.primary.withValues(alpha: 0.18),
        highlight: HavenColors.primary.withValues(alpha: 0.08),
      ),
    HavenButtonVariant.tertiary => _ButtonColors(
        bg: Colors.transparent,
        fg: HavenColors.primary,
        splash: HavenColors.primary.withValues(alpha: 0.16),
        highlight: HavenColors.primary.withValues(alpha: 0.06),
      ),
    HavenButtonVariant.destructive => _ButtonColors(
        bg: HavenColors.expired,
        fg: HavenColors.textPrimary,
        glow: HavenColors.expired,
        splash: Colors.white.withValues(alpha: 0.18),
        highlight: Colors.white.withValues(alpha: 0.08),
      ),
    HavenButtonVariant.ghost => _ButtonColors(
        bg: Colors.transparent,
        fg: HavenColors.textSecondary,
        border: HavenColors.borderHairline,
        splash: HavenColors.primary.withValues(alpha: 0.14),
        highlight: HavenColors.primary.withValues(alpha: 0.06),
      ),
  };
}
