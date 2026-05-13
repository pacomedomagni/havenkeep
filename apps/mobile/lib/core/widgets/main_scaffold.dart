import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../router/router.dart';
import 'connectivity_banner.dart';

/// App shell for the five primary tabs (Home / Warranties / Maintenance /
/// Notifications / Profile). No FAB — the "+" action lives inline inside
/// each tab where a user would naturally look for it (the Items tab has an
/// "Add item" header action; the Maintenance tab has "Log work"; etc.).
///
/// The nav bar is hand-built — Material's [BottomNavigationBar] is too
/// flat for the look we want. Each tab is a pill that animates in/out:
/// the active tab gets a soft tinted background, an animated icon swap,
/// and the label cross-fades in. The bar floats slightly off the canvas
/// edge so it reads as a distinct surface, not an OS chrome strip.
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
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom nav
// ---------------------------------------------------------------------------

const _navItems =
    <({IconData icon, IconData activeIcon, String label, String route})>[
  (
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Home',
    route: AppRoutes.dashboard,
  ),
  (
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2_rounded,
    label: 'Items',
    route: AppRoutes.items,
  ),
  (
    icon: Icons.build_outlined,
    activeIcon: Icons.build_rounded,
    label: 'Care',
    route: AppRoutes.maintenance,
  ),
  (
    icon: Icons.notifications_none_rounded,
    activeIcon: Icons.notifications_rounded,
    label: 'Alerts',
    route: AppRoutes.notifications,
  ),
  (
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    label: 'Profile',
    route: AppRoutes.settings,
  ),
];

class _HavenBottomNav extends StatelessWidget {
  const _HavenBottomNav();

  int _indexFor(String location) {
    if (location.startsWith(AppRoutes.settings) ||
        location.startsWith(AppRoutes.profile)) {
      return 4;
    }
    if (location.startsWith(AppRoutes.notifications)) return 3;
    if (location.startsWith(AppRoutes.maintenance)) return 2;
    if (location.startsWith(AppRoutes.items)) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final current = _indexFor(location);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        HavenSpacing.md,
        0,
        HavenSpacing.md,
        0,
      ),
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
          height: 64,
          child: Row(
            children: [
              for (int i = 0; i < _navItems.length; i++)
                Expanded(
                  child: _NavSlot(
                    item: _navItems[i],
                    selected: current == i,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final ({IconData icon, IconData activeIcon, String label, String route})
      item;
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
              horizontal: selected ? 10 : 8,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? HavenColors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(HavenRadius.chip),
            ),
            // 5 tabs divided across the bar leave each slot just barely
            // wider than (12 + icon + 6 + "Profile" label + 12). Wrap the
            // content in a Row that can shrink + ellipsize, and squeeze
            // the icon-to-label gap from 6 → 4 so a long label can't
            // produce sub-pixel right-side overflow bands.
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
                ClipRect(
                  child: AnimatedAlign(
                    duration: HavenMotion.medium,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    widthFactor: selected ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: AnimatedOpacity(
                        duration: HavenMotion.fast,
                        opacity: selected ? 1 : 0,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
