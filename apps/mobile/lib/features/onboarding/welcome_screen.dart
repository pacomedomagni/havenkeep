import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/havenkeep_logo.dart';
import 'forgot_password_screen.dart';

/// Welcome screen — sign up / sign in (Screen 1.2).
///
/// Single screen (no carousel) with:
/// - App logo + tagline
/// - Hero headline
/// - Apple / Google / Email auth buttons
/// - Toggle between sign-up and sign-in modes
/// - Forgot password link (sign-in mode)
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = true;
  bool _showEmailForm = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        if (mounted) _showError('Could not get Apple credentials. Please try again.');
        return;
      }

      // Build display name from Apple's provided name (only available on first sign-in)
      String? fullName;
      if (credential.givenName != null || credential.familyName != null) {
        fullName = [credential.givenName, credential.familyName]
            .where((n) => n != null && n.isNotEmpty)
            .join(' ');
        if (fullName.isEmpty) fullName = null;
      }

      await ref.read(currentUserProvider.notifier).signInWithApple(
            idToken: idToken,
            fullName: fullName,
          );
      // Navigation handled by GoRouter auth guard
    } catch (e) {
      if (e is SignInWithAppleAuthorizationException &&
          e.code == AuthorizationErrorCode.canceled) {
        // User cancelled — do nothing
        return;
      }
      if (mounted) _showError(ErrorHandler.getUserMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final account = await googleSignIn.signIn();

      if (account == null) {
        // User cancelled
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        if (mounted) _showError('Could not get Google credentials. Please try again.');
        return;
      }

      await ref.read(currentUserProvider.notifier).signInWithGoogle(
            idToken: idToken,
          );
      // Navigation handled by GoRouter auth guard
    } catch (e) {
      if (mounted) _showError(ErrorHandler.getUserMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitEmail() async {
    if (_formKey.currentState?.validate() != true) {
      HapticFeedback.lightImpact();
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        await ref.read(currentUserProvider.notifier).signUpWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              fullName: _nameController.text.trim(),
            );
      } else {
        await ref.read(currentUserProvider.notifier).signInWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      }
      // Navigation handled by GoRouter auth guard redirect
    } catch (e) {
      if (mounted) _showError(ErrorHandler.getUserMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: HavenColors.expired,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _showEmailForm = false;
      _formKey.currentState?.reset();
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
    });
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: HavenSpacing.xxl),

                // Logo
                const HavenKeepLogo(
                  size: 72,
                  showWordmark: true,
                  wordmarkColor: HavenColors.textPrimary,
                ),
                const SizedBox(height: HavenSpacing.xs),
                const Text(
                  'Your Warranties. Protected.',
                  style: TextStyle(
                    fontSize: 16,
                    color: HavenColors.textSecondary,
                  ),
                ),

                const SizedBox(height: HavenSpacing.xxl),

                // Hero headline
                Text(
                  _isSignUp
                      ? 'Never forget a\nwarranty again'
                      : 'Welcome back',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                Text(
                  _isSignUp
                      ? 'Track every appliance. Get reminders\nbefore they expire. Save money.'
                      : 'Sign in to access your warranties.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: HavenColors.textSecondary,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: HavenSpacing.xl),

                // Auth buttons
                if (Platform.isIOS) ...[
                  _buildAppleButton(),
                  const SizedBox(height: HavenSpacing.sm),
                ],
                _buildGoogleButton(),
                const SizedBox(height: HavenSpacing.sm),
                _buildEmailButton(),

                // Expandable email form
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildEmailForm(),
                  crossFadeState: _showEmailForm
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),

                const SizedBox(height: HavenSpacing.lg),

                // Toggle sign-up / sign-in
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSignUp
                          ? 'Already have an account? '
                          : "Don't have an account? ",
                      style: const TextStyle(
                        color: HavenColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleMode,
                      child: Text(
                        _isSignUp ? 'Sign in' : 'Sign up',
                        style: const TextStyle(
                          color: HavenColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: HavenSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppleButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _signInWithApple,
        icon: const Icon(Icons.apple, size: 24),
        label: Text(_isSignUp ? 'Continue with Apple' : 'Sign in with Apple'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HavenRadius.button),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _signInWithGoogle,
        icon: const Text(
          'G',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: HavenColors.textPrimary,
          ),
        ),
        label:
            Text(_isSignUp ? 'Continue with Google' : 'Sign in with Google'),
        style: OutlinedButton.styleFrom(
          foregroundColor: HavenColors.textPrimary,
          side: const BorderSide(color: HavenColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HavenRadius.button),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailButton() {
    if (_showEmailForm) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _isLoading
            ? null
            : () => setState(() => _showEmailForm = true),
        icon: const Icon(Icons.email_outlined, size: 20),
        label: Text(
          _isSignUp ? 'Sign up with Email' : 'Sign in with Email',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: HavenColors.textPrimary,
          side: const BorderSide(color: HavenColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HavenRadius.button),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm() {
    return Padding(
      padding: const EdgeInsets.only(top: HavenSpacing.md),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Full name (sign-up only)
            if (_isSignUp) ...[
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  hintText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: HavenSpacing.md),
            ],

            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email *',
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your email address';
                }
                if (!RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}$")
                    .hasMatch(value.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: HavenSpacing.md),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password *',
                hintText: _isSignUp
                    ? 'Min 8 chars, upper/lower/number/special'
                    : 'Enter your password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                if (_isSignUp) {
                  if (!RegExp(r'(?=.*[a-z])').hasMatch(value)) {
                    return 'Must include a lowercase letter';
                  }
                  if (!RegExp(r'(?=.*[A-Z])').hasMatch(value)) {
                    return 'Must include an uppercase letter';
                  }
                  if (!RegExp(r'(?=.*\d)').hasMatch(value)) {
                    return 'Must include a number';
                  }
                  if (!RegExp(r'(?=.*[@$!%*?&])').hasMatch(value)) {
                    return r'Must include a special character (@$!%*?&)';
                  }
                }
                return null;
              },
            ),

            // Forgot password link (sign-in only)
            if (!_isSignUp) ...[
              const SizedBox(height: HavenSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _openForgotPassword,
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: HavenColors.secondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: HavenSpacing.lg),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitEmail,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isSignUp ? 'Create Account' : 'Sign In'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
