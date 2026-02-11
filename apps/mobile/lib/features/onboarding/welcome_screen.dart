import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// Welcome screen — sign up / sign in (Screen 1.2).
///
/// Single screen (no carousel) with:
/// - App logo + tagline
/// - Hero headline
/// - Apple / Google / Email auth buttons
/// - Toggle between sign-up and sign-in modes
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
      await ref.read(currentUserProvider.notifier).signInWithApple();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(currentUserProvider.notifier).signInWithGoogle();
    } catch (e) {
      if (mounted) _showError(e.toString());
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
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
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
                _buildAppleButton(),
                const SizedBox(height: HavenSpacing.sm),
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
                  labelText: 'Full Name',
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
                labelText: 'Email',
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a valid email address';
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value.trim())) {
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
                labelText: 'Password',
                hintText: 'Min 8 characters',
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
                return null;
              },
            ),
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
