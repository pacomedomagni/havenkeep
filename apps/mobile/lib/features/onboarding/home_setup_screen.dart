import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

/// Home setup screen — creates the user's first home/property.
///
/// Shown after sign-up for first-time users who don't have a home yet.
/// Part of the bulk-add onboarding flow (Screens 2.1-2.5 in the spec).
class HomeSetupScreen extends ConsumerWidget {
  const HomeSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Set Up Your Home'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(HavenSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.home_outlined,
                size: 64,
                color: HavenColors.primary,
              ),
              SizedBox(height: HavenSpacing.md),
              Text(
                'Name Your Home',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),
              SizedBox(height: HavenSpacing.sm),
              // TODO: Implement home name input + bulk-add flow
              Text(
                'Home setup flow coming soon',
                style: TextStyle(color: HavenColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
