import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/widgets/haven_loader.dart';

/// Forgot password screen — request a password reset email.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  bool _isLoading = false;
  bool _emailSent = false;
  // Ch05-F086: rate-limit the resend button so a panicked user can't
  // hammer it 20 times in 5 seconds and trigger the backend's IP block.
  // 60s matches the API-side cooldown so the UI never lets them ask
  // for a token they couldn't have received yet.
  static const _resendCooldown = Duration(seconds: 60);
  int _resendSecondsRemaining = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _resendSecondsRemaining = _resendCooldown.inSeconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSecondsRemaining--;
        if (_resendSecondsRemaining <= 0) {
          timer.cancel();
          _resendSecondsRemaining = 0;
        }
      });
    });
  }

  Future<void> _requestReset() async {
    if (_formKey.currentState?.validate() != true) {
      HavenHaptics.tap();
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(currentUserProvider.notifier).forgotPassword(
            email: _emailController.text.trim(),
          );
      if (mounted) {
        setState(() => _emailSent = true);
        _startResendCooldown();
      }
    } catch (e) {
      // Always show success to prevent email enumeration (matching backend behavior)
      if (mounted) {
        setState(() => _emailSent = true);
        _startResendCooldown();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: _emailSent ? _buildSuccessState() : _buildFormState(),
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: HavenSpacing.lg),

          const Icon(
            Icons.lock_reset_outlined,
            size: 48,
            color: HavenColors.primary,
          ),
          const SizedBox(height: HavenSpacing.lg),

          const Text(
            'Reset your password',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: HavenColors.textPrimary,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),
          const Text(
            "Enter the email address associated with your account and we'll send you a link to reset your password.",
            style: TextStyle(
              fontSize: 15,
              color: HavenColors.textSecondary,
              height: 1.4,
            ),
          ),

          const SizedBox(height: HavenSpacing.xl),

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofocus: widget.initialEmail?.isEmpty ?? true,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter your email address';
              }
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),

          const SizedBox(height: HavenSpacing.lg),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _requestReset,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: HavenLoader(color: Colors.white),
                    )
                  : const Text('Send Reset Link'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: HavenSpacing.lg),

        const Icon(
          Icons.mark_email_read_outlined,
          size: 48,
          color: HavenColors.active,
        ),
        const SizedBox(height: HavenSpacing.lg),

        const Text(
          'Check your email',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: HavenColors.textPrimary,
          ),
        ),
        const SizedBox(height: HavenSpacing.sm),
        Text(
          'If an account exists for ${_emailController.text.trim()}, we sent a password reset link. Check your inbox and spam folder.',
          style: const TextStyle(
            fontSize: 15,
            color: HavenColors.textSecondary,
            height: 1.4,
          ),
        ),

        const SizedBox(height: HavenSpacing.xl),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Sign In'),
          ),
        ),

        const SizedBox(height: HavenSpacing.md),

        // Ch05-F086: cooldown-gated resend. While the timer is running
        // we render an inert label that announces the remaining seconds
        // so screen-reader users know exactly when the button reactivates.
        Center(
          child: _resendSecondsRemaining > 0
              ? Semantics(
                  liveRegion: true,
                  child: Text(
                    'You can resend in ${_resendSecondsRemaining}s',
                    style: const TextStyle(
                      color: HavenColors.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : Semantics(
                  button: true,
                  label: 'Resend password reset email',
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    child: TextButton(
                      onPressed: () => setState(() => _emailSent = false),
                      child: const Text(
                        "Didn't receive it? Try again",
                        style: TextStyle(
                          color: HavenColors.secondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
