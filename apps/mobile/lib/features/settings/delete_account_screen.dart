import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/haven_loader.dart';
import '../../core/utils/haven_haptics.dart';

/// Delete account screen — permanent account deletion with password confirmation.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _confirmed = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    if (_passwordController.text.isEmpty) {
      HavenHaptics.tap();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your password to confirm deletion'),
          backgroundColor: HavenColors.expired,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showHavenConfirmDialog(
      context,
      title: 'Delete account permanently?',
      body:
          'This will permanently delete your account and all your data including items, warranties, documents, and settings. This action cannot be undone.',
      confirmLabel: 'Delete My Account',
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(currentUserProvider.notifier).deleteAccount(
            password: _passwordController.text,
          );
      // Navigation handled by GoRouter auth guard (user becomes unauthenticated)
    } catch (e) {
      if (mounted) {
        HavenHaptics.confirm();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserMessage(e)),
            backgroundColor: HavenColors.expired,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteOAuthAccount() async {
    final confirmed = await showHavenConfirmDialog(
      context,
      title: 'Delete account permanently?',
      body:
          'This will permanently delete your account and all your data including items, warranties, documents, and settings. This action cannot be undone.',
      confirmLabel: 'Delete My Account',
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(currentUserProvider.notifier).deleteOAuthAccount();
    } catch (e) {
      if (mounted) {
        HavenHaptics.confirm();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserMessage(e)),
            backgroundColor: HavenColors.expired,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final isOAuthUser = user?.authProvider != AuthProvider.email;

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Delete Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HavenColors.expired.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(HavenRadius.button),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: HavenColors.expired,
                  size: 32,
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              const Text(
                'This action is permanent',
                style: HavenText.displayMedium,
              ),
              const SizedBox(height: HavenSpacing.sm),
              Text(
                'Deleting your account will permanently remove:',
                style: HavenText.titleMedium.copyWith(
                  color: HavenColors.textSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: HavenSpacing.md),

              // List of what will be deleted
              _buildDeletedItem('All your items and warranty records'),
              _buildDeletedItem('Uploaded documents and receipts'),
              _buildDeletedItem('Home and room configurations'),
              _buildDeletedItem('Notification preferences'),
              _buildDeletedItem('Your account and profile data'),

              const SizedBox(height: HavenSpacing.xl),

              if (isOAuthUser) ...[
                // OAuth users: delete without password, just confirm
                Text(
                  'Since you signed in with a social account, no password is needed. Just confirm below.',
                  style: HavenText.titleMedium.copyWith(
                    color: HavenColors.textSecondary,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),

                // Acknowledgement checkbox
                GestureDetector(
                  onTap: () => setState(() => _confirmed = !_confirmed),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _confirmed,
                          onChanged: (v) =>
                              setState(() => _confirmed = v ?? false),
                          activeColor: HavenColors.expired,
                        ),
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      Expanded(
                        child: Text(
                          'I understand that this action is permanent and all my data will be deleted.',
                          style: HavenText.meta.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: HavenSpacing.lg),

                // Delete button for OAuth users
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _isLoading || !_confirmed ? null : _deleteOAuthAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HavenColors.expired,
                      disabledBackgroundColor:
                          HavenColors.expired.withValues(alpha: 0.3),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: HavenLoader(color: Colors.white),
                          )
                        : const Text('Delete My Account'),
                  ),
                ),
              ] else ...[
                // Password confirmation
                Text(
                  'Enter your password to confirm:',
                  style: HavenText.titleMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),

                const SizedBox(height: HavenSpacing.lg),

                // Acknowledgement checkbox
                GestureDetector(
                  onTap: () => setState(() => _confirmed = !_confirmed),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _confirmed,
                          onChanged: (v) =>
                              setState(() => _confirmed = v ?? false),
                          activeColor: HavenColors.expired,
                        ),
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      Expanded(
                        child: Text(
                          'I understand that this action is permanent and all my data will be deleted.',
                          style: HavenText.meta.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: HavenSpacing.lg),

                // Delete button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _isLoading || !_confirmed ? null : _deleteAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HavenColors.expired,
                      disabledBackgroundColor:
                          HavenColors.expired.withValues(alpha: 0.3),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: HavenLoader(color: Colors.white),
                          )
                        : const Text('Delete My Account'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeletedItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: Row(
        children: [
          const Icon(
            Icons.remove_circle_outline,
            size: 18,
            color: HavenColors.expired,
          ),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Text(text, style: HavenText.bodySecondary),
          ),
        ],
      ),
    );
  }
}
