import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/router/router.dart';
import '../../core/utils/error_handler.dart';
import 'bulk_add/bulk_add_provider.dart';

/// Home setup screen — name your home (Screen 2.1).
///
/// First step of the bulk-add onboarding flow.
/// Creates a home record, then navigates to the room walkthrough.
class HomeSetupScreen extends ConsumerStatefulWidget {
  const HomeSetupScreen({super.key});

  @override
  ConsumerState<HomeSetupScreen> createState() => _HomeSetupScreenState();
}

class _HomeSetupScreenState extends ConsumerState<HomeSetupScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      // Create the home
      final home = Home(
        id: '', // DB generates
        userId: user.id,
        name: _nameController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final newHome = await ref.read(homesProvider.notifier).addHome(home);

      // Initialize bulk-add state
      ref.read(bulkAddProvider.notifier).setHomeId(newHome.id);

      if (mounted) {
        context.go(AppRoutes.roomSetup);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserMessage(e)),
            backgroundColor: HavenColors.expired,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancel() async {
    final bulkState = ref.read(bulkAddProvider);
    if (bulkState.totalItemCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: HavenColors.elevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HavenRadius.card),
          ),
          title: const Text('Discard setup?'),
          content: Text(
            'You\'ve selected ${bulkState.totalItemCount} items across '
            '${bulkState.roomsWithItemsCount} rooms.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Going'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: HavenColors.expired,
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    ref.read(bulkAddProvider.notifier).reset();
    if (mounted) context.go(AppRoutes.firstAction);
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _nameController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancel,
        ),
        title: const Text(''),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: HavenSpacing.lg),

                // Headline
                const Text(
                  "Let's walk through\nyour home",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: HavenSpacing.xl),

                // Label
                const Text(
                  'What do you call this place?',
                  style: TextStyle(
                    fontSize: 16,
                    color: HavenColors.textSecondary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),

                // Name input
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: "e.g. 'Our House'",
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Give your home a name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: HavenSpacing.lg),

                // Helper text
                const Text(
                  "We'll go room by room. Tap the appliances you have — takes about 5 minutes.",
                  style: TextStyle(
                    fontSize: 14,
                    color: HavenColors.textTertiary,
                    height: 1.4,
                  ),
                ),

                const Spacer(),

                // Start button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_isLoading || !hasText) ? null : _startSetup,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Start with Kitchen →'),
                  ),
                ),

                const SizedBox(height: HavenSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
