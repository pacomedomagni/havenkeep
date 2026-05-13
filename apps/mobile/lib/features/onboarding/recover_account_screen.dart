import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/haven_loader.dart';

/// C0-14: surfaced by the welcome screen when `/auth/login` returns 403
/// ACCOUNT_PENDING_DELETION. The user is in their 30-day cooling-off
/// window and presented a valid password (or OAuth identity), so we
/// know they're the right person — they just need to choose between
/// "keep my account" and "go through with the deletion."
///
/// The recovery token is single-use, 15-minute TTL. If it expires
/// before the user taps Cancel deletion, they'll have to log in
/// again to mint a fresh one.
class RecoverAccountScreen extends ConsumerStatefulWidget {
  const RecoverAccountScreen({
    super.key,
    required this.recoveryToken,
    required this.email,
  });

  /// JWT minted by the API with `purpose: 'account_recover'`. Sent as
  /// a Bearer token on `/users/me/recover`.
  final String recoveryToken;

  /// Email the user just signed in with — shown in the body so they
  /// can confirm it's the right account before tapping Cancel.
  final String email;

  @override
  ConsumerState<RecoverAccountScreen> createState() =>
      _RecoverAccountScreenState();
}

class _RecoverAccountScreenState extends ConsumerState<RecoverAccountScreen> {
  bool _isLoading = false;
  bool _recovered = false;
  String? _errorMessage;

  Future<void> _recoverAccount() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(currentUserProvider.notifier)
          .recoverAccount(widget.recoveryToken);
      if (!mounted) return;
      HavenHaptics.confirm();
      setState(() {
        _recovered = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          color: HavenColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.lg),
          child: _recovered ? _buildSuccess() : _buildPrompt(),
        ),
      ),
    );
  }

  Widget _buildPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: HavenSpacing.xl),
        const Icon(
          Icons.history,
          size: 64,
          color: HavenColors.expiring,
        ),
        const SizedBox(height: HavenSpacing.lg),
        const Text(
          'Your account is scheduled for deletion',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
          ),
        ),
        const SizedBox(height: HavenSpacing.md),
        Text(
          'We were getting ready to permanently delete the account for '
          '${widget.email}. You still have time to cancel — tap below to '
          'restore everything. If you do nothing, the account and all its '
          'data will be deleted at the end of the 30-day cooling-off window.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: HavenColors.textSecondary,
            height: 1.4,
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: HavenSpacing.lg),
          Container(
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.expired.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: HavenColors.expired.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 14,
                color: HavenColors.expired,
              ),
            ),
          ),
        ],
        const SizedBox(height: HavenSpacing.xl),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _recoverAccount,
            style: ElevatedButton.styleFrom(
              backgroundColor: HavenColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const HavenLoader(size: 24)
                : const Text(
                    'Cancel deletion and keep my account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: HavenSpacing.md),
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Not now',
            style: TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: HavenSpacing.xl),
        const Icon(
          Icons.check_circle,
          size: 64,
          color: HavenColors.active,
        ),
        const SizedBox(height: HavenSpacing.lg),
        const Text(
          'Account restored',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
          ),
        ),
        const SizedBox(height: HavenSpacing.md),
        const Text(
          'Welcome back. Sign in again to continue where you left off.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: HavenColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: HavenSpacing.xl),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: HavenColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Back to sign in',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
