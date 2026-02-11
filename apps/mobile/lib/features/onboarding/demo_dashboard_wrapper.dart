import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/demo_mode_provider.dart';
import '../home/dashboard_screen.dart';

/// Wraps the dashboard with interactive demo callouts and "Exit Demo" CTA.
class DemoDashboardWrapper extends ConsumerStatefulWidget {
  final VoidCallback onExitDemo;

  const DemoDashboardWrapper({
    super.key,
    required this.onExitDemo,
  });

  @override
  ConsumerState<DemoDashboardWrapper> createState() =>
      _DemoDashboardWrapperState();
}

class _DemoDashboardWrapperState extends ConsumerState<DemoDashboardWrapper> {
  bool _showHint = true;

  @override
  void initState() {
    super.initState();
    // Auto-dismiss hint after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showHint = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.read(demoModeProvider.notifier).getStats();

    return Stack(
      children: [
        // Actual dashboard (with demo data)
        const DashboardScreen(),

        // Demo indicator banner at top
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  HavenColors.accent.withValues(alpha: 0.9),
                  HavenColors.accentSecondary.withValues(alpha: 0.9),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const Icon(Icons.play_circle_outline,
                      color: HavenColors.textPrimary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Interactive Demo Mode',
                      style: TextStyle(
                        color: HavenColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _showExitConfirmation(context);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: HavenColors.textPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      backgroundColor: HavenColors.textPrimary.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Exit Demo'),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Simple hint (auto-dismisses)
        if (_showHint)
          Positioned(
            top: 120,
            left: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => setState(() => _showHint = false),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HavenColors.accent.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: HavenColors.accent.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        color: HavenColors.textPrimary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This is demo data. Try exploring to see how HavenKeep works!',
                        style: TextStyle(
                          fontSize: 14,
                          color: HavenColors.textPrimary.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: HavenColors.textPrimary, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _showHint = false),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Sticky CTA at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HavenColors.surface,
              boxShadow: [
                BoxShadow(
                  color: HavenColors.background.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Protecting \$${stats.totalValue.toStringAsFixed(0)} in warranties',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: HavenColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Ready to protect your own items?',
                              style: TextStyle(
                                fontSize: 14,
                                color: HavenColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _showExitConfirmation(context);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: HavenColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Sign Up - It\u2019s Free',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Demo Mode?'),
        content: const Text(
          'Ready to create your free account and start protecting your own warranties?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Stay in Demo'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(demoModeProvider.notifier).exitDemoMode();
              widget.onExitDemo();
            },
            child: const Text('Sign Up'),
          ),
        ],
      ),
    );
  }
}
