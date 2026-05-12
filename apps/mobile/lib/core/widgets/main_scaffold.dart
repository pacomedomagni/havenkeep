import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../router/router.dart';
import '../utils/haven_haptics.dart';
import 'connectivity_banner.dart';

/// App shell for the three primary tabs (Home / Warranties / Maintenance)
/// plus the centered "+" FAB that opens the add-item flow.
///
/// The nav bar is hand-built — Material's [BottomNavigationBar] is too
/// flat for the look we want. Instead: a frosted bar that floats slightly
/// off the canvas edge, a pill that slides behind the active tab, the
/// label cross-fading in only for the active item, and a gradient FAB with
/// a soft indigo glow that notches into the bar.
class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: const _HavenBottomNav(),
      floatingActionButton: const _HavenFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

// ---------------------------------------------------------------------------
// FAB
// ---------------------------------------------------------------------------

class _HavenFab extends StatelessWidget {
  const _HavenFab();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: HavenGradients.brand,
        boxShadow: HavenElevation.glow(HavenColors.primary, strength: 1.4),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HavenHaptics.tap();
            context.push(AppRoutes.addItem);
          },
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Semantics(
            button: true,
            label: 'Add warranty',
            child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom nav
// ---------------------------------------------------------------------------

const _navItems = <({IconData icon, IconData activeIcon, String label, String route})>[
  (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', route: AppRoutes.dashboard),
  (icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2_rounded, label: 'Warranties', route: AppRoutes.items),
  (icon: Icons.build_outlined, activeIcon: Icons.build_rounded, label: 'Maintenance', route: AppRoutes.maintenance),
];

class _HavenBottomNav extends StatelessWidget {
  const _HavenBottomNav();

  int _indexFor(String location) {
    if (location.startsWith(AppRoutes.maintenance)) return 2;
    if (location.startsWith(AppRoutes.items)) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final current = _indexFor(location);

    return Container(
      // Float the bar a hair off the canvas so the FAB glow has room and
      // the bar reads as a distinct surface, not the screen edge.
      margin: const EdgeInsets.fromLTRB(HavenSpacing.md, 0, HavenSpacing.md, 0),
      decoration: BoxDecoration(
        color: HavenColors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HavenRadius.card + 6),
        ),
        border: const Border(
          top: BorderSide(color: HavenColors.borderHairline),
          left: BorderSide(color: HavenColors.borderHairline),
          right: BorderSide(color: HavenColors.borderHairline),
        ),
        boxShadow: HavenElevation.shadowFor(2),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(child: _NavSlot(item: _navItems[0], selected: current == 0)),
              Expanded(child: _NavSlot(item: _navItems[1], selected: current == 1)),
              // Spacer under the docked FAB.
              const SizedBox(width: 64),
              Expanded(child: _NavSlot(item: _navItems[2], selected: current == 2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final ({IconData icon, IconData activeIcon, String label, String route}) item;
  final bool selected;

  const _NavSlot({required this.item, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = selected ? HavenColors.primary : HavenColors.textTertiary;

    return Semantics(
      label: item.label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          if (!selected) HavenHaptics.tap();
          context.go(item.route);
        },
        radius: 36,
        highlightShape: BoxShape.rectangle,
        containedInkWell: true,
        child: Center(
          child: AnimatedContainer(
            duration: HavenMotion.medium,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 14 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? HavenColors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(HavenRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: HavenMotion.fast,
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    key: ValueKey(selected),
                    color: color,
                    size: 22,
                  ),
                ),
                // Label slides in only for the active tab.
                ClipRect(
                  child: AnimatedAlign(
                    duration: HavenMotion.medium,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    widthFactor: selected ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: AnimatedOpacity(
                        duration: HavenMotion.fast,
                        opacity: selected ? 1 : 0,
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: HavenColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
