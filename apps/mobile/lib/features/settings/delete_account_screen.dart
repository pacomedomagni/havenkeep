import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../main.dart' show environmentConfigProvider;
import '../../core/providers/auth_provider.dart';
import '../../core/services/auth_repository.dart';
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
  final _typeToConfirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _confirmed = false;
  bool _typedDelete = false;

  /// The literal phrase we require the user to type to acknowledge an
  /// irreversible delete. Mirrors the admin-side pattern from Phase 4.
  static const _confirmPhrase = 'DELETE';

  @override
  void initState() {
    super.initState();
    _typeToConfirmController.addListener(() {
      final next = _typeToConfirmController.text.trim() == _confirmPhrase;
      if (next != _typedDelete) {
        setState(() => _typedDelete = next);
      }
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _typeToConfirmController.dispose();
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
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

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
      // Re-authenticate against the original IdP and confirm the
      // verified subject id matches the locally signed-in user before
      // we trust a JWT alone for an irreversible delete.
      final reauthOk = await _reauthenticateOAuth(user);
      if (!reauthOk) {
        if (mounted) {
          HavenHaptics.confirm();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Re-authentication failed. Please sign in again to delete your account.'),
              backgroundColor: HavenColors.expired,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

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

  /// Force a fresh sign-in with the user's OAuth provider and verify the
  /// returned identity resolves to the same backend user record. Returns
  /// false on cancel, mismatch, or any IdP error.
  Future<bool> _reauthenticateOAuth(User user) async {
    try {
      final repo = ref.read(authRepositoryProvider);
      switch (user.authProvider) {
        case AuthProvider.google:
          return await _reauthGoogle(repo, user);
        case AuthProvider.apple:
          return await _reauthApple(repo, user);
        case AuthProvider.email:
          // Unreachable for OAuth flow, but keeping the switch exhaustive.
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<bool> _reauthGoogle(AuthRepository repo, User user) async {
    final serverClientId =
        ref.read(environmentConfigProvider).googleServerClientId;
    final googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: serverClientId.isNotEmpty ? serverClientId : null,
    );
    // Force a fresh prompt — never reuse a cached credential for delete.
    await googleSignIn.signOut();
    final account = await googleSignIn.signIn();
    if (account == null) return false;
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) return false;

    final reauthed = await repo.signInWithGoogle(idToken: idToken);
    return reauthed != null && reauthed.id == user.id;
  }

  Future<bool> _reauthApple(AuthRepository repo, User user) async {
    final config = ref.read(environmentConfigProvider);
    WebAuthenticationOptions? webOptions;
    if (!Platform.isIOS) {
      if (config.appleServicesId.isEmpty || config.appleRedirectUri.isEmpty) {
        return false;
      }
      webOptions = WebAuthenticationOptions(
        clientId: config.appleServicesId,
        redirectUri: Uri.parse(config.appleRedirectUri),
      );
    }
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      webAuthenticationOptions: webOptions,
    );
    final idToken = credential.identityToken;
    if (idToken == null) return false;

    final reauthed = await repo.signInWithApple(idToken: idToken);
    return reauthed != null && reauthed.id == user.id;
  }

  /// If the user is on Premium and has unused subscription days, surface
  /// the count so they understand the trade-off of deleting now.
  String? _premiumWarningMessage(User? user) {
    if (user == null) return null;
    if (user.plan != UserPlan.premium) return null;
    final expiresAt = user.planExpiresAt;
    if (expiresAt == null) return null;
    final daysLeft = expiresAt.difference(DateTime.now()).inDays;
    if (daysLeft <= 0) return null;
    final dayWord = daysLeft == 1 ? 'day' : 'days';
    return 'You still have $daysLeft $dayWord of Premium left. '
        'Deleting now forfeits the remaining time — there is no refund.';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final isOAuthUser = user?.authProvider != AuthProvider.email;
    final premiumWarning = _premiumWarningMessage(user);

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

              if (premiumWarning != null) ...[
                const SizedBox(height: HavenSpacing.md),
                Container(
                  padding: const EdgeInsets.all(HavenSpacing.md),
                  decoration: BoxDecoration(
                    color: HavenColors.expiring.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(HavenRadius.card),
                    border: Border.all(
                      color: HavenColors.expiring.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.workspace_premium_outlined,
                        color: HavenColors.expiring,
                        size: 20,
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      Expanded(
                        child: Text(
                          premiumWarning,
                          style: HavenText.meta.copyWith(
                            color: HavenColors.expiring,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: HavenSpacing.xl),

              // Type-DELETE confirmation — required for both email and OAuth
              // flows. Matches the destructive-confirm pattern from Phase 4.
              Text(
                'Type "$_confirmPhrase" to confirm:',
                style: HavenText.titleMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: HavenSpacing.sm),
              TextFormField(
                controller: _typeToConfirmController,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: _confirmPhrase,
                  prefixIcon: Icon(Icons.warning_amber_rounded),
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              if (isOAuthUser) ...[
                // OAuth users: re-authenticate with their IdP — no password.
                Text(
                  'You will be asked to sign in with ${user?.authProvider.displayLabel ?? 'your social account'} to verify it is you.',
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
                    onPressed: _isLoading || !_confirmed || !_typedDelete
                        ? null
                        : _deleteOAuthAccount,
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
                    onPressed: _isLoading || !_confirmed || !_typedDelete
                        ? null
                        : _deleteAccount,
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
