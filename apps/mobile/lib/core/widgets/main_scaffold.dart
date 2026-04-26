import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import '../router/router.dart';
import 'connectivity_banner.dart';

/// Main scaffold with bottom navigation bar, centered FAB, and connectivity banner.
///
/// This is the shell for the two main tabs: Home (Dashboard) and Items.
/// The FAB ("+") opens the Add Item flow.
class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: _BottomNav(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.addItem),
        tooltip: 'Add warranty',
        backgroundColor: HavenColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = location.startsWith(AppRoutes.maintenance)
        ? 2
        : location.startsWith(AppRoutes.items)
            ? 1
            : 0;

    return BottomAppBar(
      color: HavenColors.surface,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Home tab
          Expanded(
            child: _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              label: 'Home',
              isSelected: currentIndex == 0,
              onTap: () => context.go(AppRoutes.dashboard),
            ),
          ),

          // Warranties tab
          Expanded(
            child: _NavItem(
              icon: Icons.inventory_2_outlined,
              activeIcon: Icons.inventory_2,
              label: 'Warranties',
              isSelected: currentIndex == 1,
              onTap: () => context.go(AppRoutes.items),
            ),
          ),

          // Spacer for centered FAB
          const SizedBox(width: 48),

          // Maintenance tab
          Expanded(
            child: _NavItem(
              icon: Icons.build_outlined,
              activeIcon: Icons.build,
              label: 'Maintenance',
              isSelected: currentIndex == 2,
              onTap: () => context.go(AppRoutes.maintenance),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? HavenColors.primary : HavenColors.textTertiary;

    return Semantics(
      label: label,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        // Tighter vertical rhythm so a 24px icon + 12px label + spacer
        // fit inside BottomAppBar's default 60px height. Previous 8/4
        // padding overflowed by ~5px on iOS 26 — visible as a red
        // "BOTTOM OVERFLOWED" indicator in debug builds + a faint hairline
        // in release.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: color,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
