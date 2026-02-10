import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// HavenKeep brand logo widget.
///
/// Renders the shield-house-checkmark logo from SVG asset.
/// Falls back to a styled icon if SVG can't be loaded.
class HavenKeepLogo extends StatelessWidget {
  /// Size of the logo icon (width & height).
  final double size;

  /// Whether to show the wordmark next to the icon.
  final bool showWordmark;

  /// Text color for the wordmark.
  final Color? wordmarkColor;

  const HavenKeepLogo({
    super.key,
    this.size = 48,
    this.showWordmark = false,
    this.wordmarkColor,
  });

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.asset(
      'assets/images/logo-icon.svg',
      width: size,
      height: size,
      placeholderBuilder: (_) => _FallbackIcon(size: size),
    );

    if (!showWordmark) return icon;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 12),
        Text(
          'HavenKeep',
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
            color: wordmarkColor ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Fallback when the SVG asset is unavailable.
class _FallbackIcon extends StatelessWidget {
  final double size;
  const _FallbackIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.shield_outlined,
      size: size,
      color: const Color(0xFF6366F1),
    );
  }
}
