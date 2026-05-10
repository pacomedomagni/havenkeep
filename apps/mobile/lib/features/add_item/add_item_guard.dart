import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';

/// H57: every direct add-item screen wraps its body in this widget so
/// a free-plan user can't bypass the gateway via deep link, push, or
/// dashboard CTA. The gate is the same `isAtItemLimitProvider` the
/// gateway screen used to enforce solo.
///
/// Behaviour:
///   - loading  → spinner
///   - error    → "Try again" with the same fail-closed framing the
///                gateway already uses
///   - at limit → "Free plan limit reached" with a route back to
///                the gateway (which shows the upgrade CTA)
///   - otherwise → the supplied [child]
class AddItemGuard extends ConsumerWidget {
  final Widget child;
  const AddItemGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final atLimitAsync = ref.watch(isAtItemLimitProvider);
    return atLimitAsync.when(
      loading: () => const Scaffold(
        backgroundColor: HavenColors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: HavenColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: HavenColors.expired),
                  const SizedBox(height: HavenSpacing.md),
                  const Text(
                    "We couldn't check your plan",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  const Text(
                    "Try again in a moment so we don't accidentally let you past your free-plan cap.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: HavenColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => ref.invalidate(isAtItemLimitProvider),
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      data: (isAtLimit) {
        if (!isAtLimit) return child;
        // At free-plan limit. Show a stock "upgrade" screen instead of
        // the requested add flow. Closing returns to wherever the user
        // came from; "See upgrade options" routes to the gateway.
        return Scaffold(
          backgroundColor: HavenColors.background,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(HavenSpacing.lg),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 64, color: HavenColors.primary),
                    const SizedBox(height: HavenSpacing.md),
                    const Text(
                      "You've reached the free-plan limit",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),
                    const Text(
                      'Upgrade to Premium to add unlimited items, scan receipts with AI, and manage every property in your portfolio.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: HavenColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('See upgrade options'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
