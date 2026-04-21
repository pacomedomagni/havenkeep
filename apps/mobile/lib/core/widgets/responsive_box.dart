import 'package:flutter/material.dart';

/// Caps content width on tablets/foldables so it doesn't stretch edge-to-edge.
/// Wrap any scrollable column or form in this to get a polished tablet layout
/// without per-screen tablet logic.
///
/// Phones render unchanged (content still fills the width). On widths above
/// [breakpoint], the child is centered inside a constrained box.
class ResponsiveBox extends StatelessWidget {
  final Widget child;

  /// Max content width in logical pixels once we're above [breakpoint].
  final double maxWidth;

  /// Switching threshold — iPad Mini portrait is 744 logical px.
  final double breakpoint;

  /// Horizontal padding to apply when the device is wider than [breakpoint].
  /// Defaults to 24, which feels right for tablet forms.
  final double tabletHorizontalPadding;

  const ResponsiveBox({
    super.key,
    required this.child,
    this.maxWidth = 640,
    this.breakpoint = 600,
    this.tabletHorizontalPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= breakpoint;
        if (!isWide) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tabletHorizontalPadding,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Simple breakpoints for screens that want to adapt more aggressively
/// (e.g. show a grid on tablet, a list on phone).
enum HavenBreakpoint { phone, tablet, desktop }

extension HavenBreakpoints on BuildContext {
  HavenBreakpoint get breakpoint {
    final w = MediaQuery.sizeOf(this).width;
    if (w >= 1100) return HavenBreakpoint.desktop;
    if (w >= 600) return HavenBreakpoint.tablet;
    return HavenBreakpoint.phone;
  }

  bool get isTabletOrWider => breakpoint != HavenBreakpoint.phone;
}
