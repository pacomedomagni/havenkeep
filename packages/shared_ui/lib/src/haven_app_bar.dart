import 'package:flutter/material.dart';

import 'theme.dart';

/// The single app-bar primitive for HavenKeep. Wraps Material's [AppBar]
/// so screens stop hand-rolling title styles, subtle scroll-under shading,
/// and back-button positioning. Same rules every screen: 18px/700 title,
/// left-aligned, transparent canvas, no Material scroll-under tint.
///
/// Two shapes:
///   * Default — single line title.
///   * [HavenAppBar.large] — display-large title that scales down on
///     scroll, like iOS large-title nav bars. Use on top-level tab roots
///     (the dashboard, items list, settings landing).
///
/// ```dart
/// Scaffold(
///   appBar: const HavenAppBar(title: 'Settings'),
///   body: ...,
/// )
/// Scaffold(
///   appBar: HavenAppBar.large(
///     title: 'Warranties',
///     subtitle: 'Track every item in your home',
///   ),
///   body: ...,
/// )
/// ```
class HavenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool _large;

  const HavenAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  })  : subtitle = null,
        _large = false;

  const HavenAppBar.large({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  }) : _large = true;

  @override
  Size get preferredSize => _large
      ? Size.fromHeight(subtitle == null ? 84 : 104)
      : const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (!_large) {
      return AppBar(
        title: Text(title),
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
      );
    }

    final canPop = automaticallyImplyLeading && Navigator.of(context).canPop();
    return SizedBox(
      height: preferredSize.height + MediaQuery.paddingOf(context).top,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            HavenSpacing.md,
            HavenSpacing.sm,
            HavenSpacing.md,
            HavenSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null)
                leading!
              else if (canPop)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  color: HavenColors.textPrimary,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: HavenText.displayLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: HavenText.bodySecondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}
