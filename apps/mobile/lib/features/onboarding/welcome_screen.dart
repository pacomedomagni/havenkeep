import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

/// Welcome screen — sign up / sign in.
///
/// Single screen (no carousel) with:
/// - App logo + tagline
/// - Apple Sign-In button
/// - Google Sign-In button
/// - Email sign-in option (expands inline)
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo
              const Icon(
                Icons.shield_outlined,
                size: 72,
                color: HavenColors.primary,
              ),
              const SizedBox(height: HavenSpacing.md),
              const Text(
                'HavenKeep',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),
              const SizedBox(height: HavenSpacing.xs),
              const Text(
                'Your Warranties. Protected.',
                style: TextStyle(
                  fontSize: 16,
                  color: HavenColors.textSecondary,
                ),
              ),

              const Spacer(),

              // TODO: Implement auth buttons
              // - Sign in with Apple
              // - Sign in with Google
              // - Sign in with Email (expandable)
              const Text(
                'Auth buttons coming soon',
                style: TextStyle(color: HavenColors.textTertiary),
              ),

              const SizedBox(height: HavenSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
