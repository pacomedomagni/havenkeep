import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/demo_mode_provider.dart';
import '../../core/router/router.dart';

/// Developer-only options surfaced via 5-tap on the version label in
/// settings. Houses the runtime demo-mode toggle (C202) and any future
/// build-flavor tweaks the QA / engineering team might want without
/// shipping a separate build.
class DeveloperOptionsScreen extends ConsumerWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demoEnabled = ref.watch(demoModeProvider).isEnabled;

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Developer options'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(HavenSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: HavenSpacing.md,
              vertical: HavenSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: HavenColors.surface,
              borderRadius: BorderRadius.circular(HavenRadius.card),
              border: Border.all(color: HavenColors.border),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: demoEnabled,
              activeThumbColor: HavenColors.primary,
              title: const Text(
                'Demo Mode',
                style: HavenText.titleMedium,
              ),
              subtitle: const Text(
                'Replaces all data with fixture warranties. No network calls.',
                style: HavenText.caption,
              ),
              onChanged: (value) {
                final notifier = ref.read(demoModeProvider.notifier);
                if (value) {
                  notifier.enterDemoMode();
                  if (context.mounted) {
                    context.go(AppRoutes.demo);
                  }
                } else {
                  notifier.exitDemoMode();
                  if (context.mounted) {
                    context.go(AppRoutes.welcome);
                  }
                }
              },
            ),
          ),
          const SizedBox(height: HavenSpacing.md),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: HavenSpacing.sm),
            child: Text(
              'These options are intended for engineering and QA. They are '
              'always available — there is no separate "release" build that '
              'hides them — so use with care.',
              style: HavenText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
