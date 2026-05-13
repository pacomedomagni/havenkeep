import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../main.dart' show environmentConfigProvider;
import '../../core/providers/auth_provider.dart';
import '../../core/utils/apple_sign_in_nonce.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/havenkeep_logo.dart';
import 'forgot_password_screen.dart';
import 'recover_account_screen.dart';
import '../../core/widgets/haven_loader.dart';

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
  bool _loginFailed = false;
  String? _pendingReferralCode;

  @override
  void initState() {
    super.initState();
    // The router rewrites unauthenticated `/referral/:code` deep links
    // to `/welcome?pendingReferral=$code` (C102) so the auth gate runs
    // before any account is created. Persist the code now so the email
    // sign-up below picks it up just like the handler screen used to.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final params = GoRouterState.of(context).uri.queryParameters;
      final code = params['pendingReferral'];
      // Ch05-F079: surface the pending referral in the UI as well — a
      // silent persistence misses the chance to confirm the user
      // landed via the right code, and a failed/garbled code stays
      // invisible until they try to sign up.
      String? resolved = (code != null && code.isNotEmpty) ? code : null;
      final prefs = await SharedPreferences.getInstance();
      if (resolved != null) {
        await prefs.setString('referral_code', resolved);
      } else {
        // Show any code already stored from a prior referral handler
        // visit so the banner stays consistent across cold starts.
        resolved = prefs.getString('referral_code');
      }
      // H62: the router rewrites unauthenticated `/gift/<code>` deep
      // links to `/welcome?pendingGift=$code`. Persist the gift code so
      // that after sign-up we can resume the activation flow even
      // though the gift activation screen itself never got a chance to
      // stash it (cold start lands on /welcome directly).
      final giftCode = params['pendingGift'];
      if (giftCode != null && giftCode.isNotEmpty) {
        await prefs.setString('pending_gift_code', giftCode);
      }
      if (!mounted) return;
      if (resolved != null && resolved.isNotEmpty) {
        setState(() => _pendingReferralCode = resolved);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    // Hoisted so the C0-14 catch branch below can pass the email to
    // the recover screen if Apple surfaced it. Apple only returns
    // email on first sign-in; subsequent calls leave this empty.
    String credentialEmail = '';
    try {
      // iOS uses the native Apple Sign-In flow; everything else (Android,
      // web, desktop) goes through Apple's web OAuth flow which needs a
      // Services ID + return URL configured in the Apple Developer Portal.
      final config = ref.read(environmentConfigProvider);
      WebAuthenticationOptions? webOptions;
      if (!Platform.isIOS) {
        if (config.appleServicesId.isEmpty || config.appleRedirectUri.isEmpty) {
          if (mounted) _showError('Apple Sign-In is not configured for this platform.');
          return;
        }
        webOptions = WebAuthenticationOptions(
          clientId: config.appleServicesId,
          redirectUri: Uri.parse(config.appleRedirectUri),
        );
      }

      // S1-H: per-attempt random nonce. Pass the SHA-256 to Apple's SDK and
      // the unhashed value to the API so the server can verify the token's
      // `nonce` claim and reject replays.
      final appleNonce = AppleSignInNonce.generate();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: appleNonce.hashed,
        webAuthenticationOptions: webOptions,
      );
      credentialEmail = credential.email ?? '';

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

      // H63: forward the pending referral code on first-sign-up so the
      // attribution path matches the email flow. The server ignores it
      // for returning users; we still wipe it locally below so a second
      // sign-in doesn't keep re-asserting the same code.
      final prefs = await SharedPreferences.getInstance();
      final referralCode = prefs.getString('referral_code');
      await ref.read(currentUserProvider.notifier).signInWithApple(
            idToken: idToken,
            nonce: appleNonce.raw,
            fullName: fullName,
            referralCode: referralCode,
          );
      if (referralCode != null) {
        await prefs.remove('referral_code');
      }
      // H62: if the user came in via a `/gift/<code>` deep link, route
      // them back to activate. Otherwise fall through and let the auth
      // guard pick the destination.
      if (await _resumePendingGiftCode()) return;
      // Navigation handled by GoRouter auth guard
    } catch (e) {
      if (e is SignInWithAppleAuthorizationException &&
          e.code == AuthorizationErrorCode.canceled) {
        // User cancelled — do nothing
        return;
      }
      // C0-14: route a within-grace soft-deleted login to the recover
      // screen. Apple only returns email on first sign-in, so this
      // may be empty on subsequent attempts — the screen handles that.
      if (await _handleAccountPendingDeletion(e, credentialEmail)) {
        return;
      }
      if (mounted) _showError(ErrorHandler.getUserMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    // Hoisted so the C0-14 catch branch below can pass the email to
    // the recover screen.
    String googleEmail = '';
    try {
      // serverClientId is the Web OAuth client ID Firebase auto-creates in
      // the linked Cloud project. Passing it makes the resulting idToken's
      // `aud` match what the backend `/auth/google` endpoint verifies
      // against — required for Google Sign-In to work on Android, and the
      // recommended pattern on iOS too.
      final serverClientId = ref.read(environmentConfigProvider).googleServerClientId;
      final googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: serverClientId.isNotEmpty ? serverClientId : null,
      );
      final account = await googleSignIn.signIn();

      if (account == null) {
        // User cancelled
        return;
      }
      googleEmail = account.email;

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        if (mounted) _showError('Could not get Google credentials. Please try again.');
        return;
      }

      // H63: same as the Apple path — forward the pending referral code so
      // OAuth signups attribute correctly.
      final prefs = await SharedPreferences.getInstance();
      final referralCode = prefs.getString('referral_code');
      await ref.read(currentUserProvider.notifier).signInWithGoogle(
            idToken: idToken,
            referralCode: referralCode,
          );
      if (referralCode != null) {
        await prefs.remove('referral_code');
      }
      // H62: resume the gift activation flow if we came in via /gift/...
      if (await _resumePendingGiftCode()) return;
      // Navigation handled by GoRouter auth guard
    } catch (e) {
      // C0-14: route a within-grace soft-deleted login to the recover
      // screen instead of showing the generic error toast.
      if (await _handleAccountPendingDeletion(e, googleEmail)) return;
      if (mounted) _showError(ErrorHandler.getUserMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitEmail() async {
    if (_formKey.currentState?.validate() != true) {
      HavenHaptics.tap();
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        final prefs = await SharedPreferences.getInstance();
        final referralCode = prefs.getString('referral_code');

        await ref.read(currentUserProvider.notifier).signUpWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              fullName: _nameController.text.trim(),
              referralCode: referralCode,
            );
        if (referralCode != null) {
          await prefs.remove('referral_code');
        }
      } else {
        await ref.read(currentUserProvider.notifier).signInWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      }
      // H62: resume the gift activation flow if we came in via /gift/...
      if (await _resumePendingGiftCode()) return;
      // Navigation handled by GoRouter auth guard redirect
    } catch (e) {
      // C0-14: route a within-grace soft-deleted login to the recover
      // screen. Don't flip _loginFailed in this case — the login
      // wasn't a "wrong credentials" failure.
      if (await _handleAccountPendingDeletion(e, _emailController.text.trim())) {
        return;
      }
      if (mounted) {
        if (!_isSignUp) setState(() => _loginFailed = true);
        _showError(ErrorHandler.getUserMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// H62: after a successful sign-up/sign-in, resume the gift-activation
  /// deep link the visitor came in on. The gift activation screen stashes
  /// the code in `pending_gift_code` whenever an unauthenticated user
  /// lands on `/gift/<code>`; without this resume, the user signs up and
  /// drops into the dashboard with no path back to the gift they were
  /// trying to redeem. Returning true tells the caller to skip the
  /// default "navigation handled by GoRouter" comment — we just routed.
  Future<bool> _resumePendingGiftCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('pending_gift_code');
    if (code == null || code.isEmpty) return false;
    // Don't clear the key here — the gift activation screen wipes it on
    // a successful verify+activate. Clearing now would orphan a partial
    // flow if the user backed out before activating.
    if (!mounted) return false;
    context.go('/gift/${Uri.encodeComponent(code)}');
    return true;
  }

  /// C0-14: if the caught exception is the typed
  /// [ApiAccountPendingDeletionException] thrown by `/auth/login` when a
  /// soft-deleted user re-authenticates within the 30-day grace window,
  /// route to [RecoverAccountScreen] and return true so the caller skips
  /// the generic error path. Returns false otherwise — the caller still
  /// owns the error UX.
  Future<bool> _handleAccountPendingDeletion(Object error, String email) async {
    if (error is! ApiAccountPendingDeletionException) return false;
    if (!mounted) return true;
    HavenHaptics.confirm();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecoverAccountScreen(
          recoveryToken: error.recoveryToken,
          email: email,
        ),
      ),
    );
    return true;
  }

  void _showError(String message) {
    HavenHaptics.confirm();
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
      _loginFailed = false;
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
      backgroundColor: HavenColors.canvas,
      body: Stack(
        children: [
          // A soft indigo glow bleeding down from the top — gives the dark
          // canvas depth instead of being a flat black wall.
          Positioned(
            top: -160,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 360,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.0,
                    colors: [
                      HavenColors.primary.withValues(alpha: 0.22),
                      HavenColors.canvas.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: HavenSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: HavenSpacing.xl),

                    // Logo — with a faint glow ring.
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow:
                            HavenElevation.glow(HavenColors.primary, strength: 0.7),
                      ),
                      child: const HavenKeepLogo(
                        size: 64,
                        showWordmark: false,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.xl),

                    // Hero headline — the moment.
                    Text(
                      _isSignUp
                          ? 'Never forget a\nwarranty again'
                          : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: HavenText.hero.copyWith(fontSize: 30, height: 1.15),
                    ),
                    const SizedBox(height: HavenSpacing.sm + 2),
                    Text(
                      _isSignUp
                          ? 'Track every appliance. Get reminders before they expire. Save money.'
                          : 'Sign in to access your warranties.',
                      textAlign: TextAlign.center,
                      style: HavenText.bodySecondary.copyWith(fontSize: 15),
                    ),

                    if (_pendingReferralCode != null) ...[
                      const SizedBox(height: HavenSpacing.md),
                      _buildReferralBanner(_pendingReferralCode!),
                    ],

                    const SizedBox(height: HavenSpacing.xl),

                    // Auth buttons — Apple is the prominent CTA (white,
                    // glow); Google + email are quiet outlined alternates.
                    _buildAppleButton(),
                    const SizedBox(height: HavenSpacing.sm + 2),
                    Row(
                      children: [
                        Expanded(child: _buildGoogleButton()),
                        if (!_showEmailForm) ...[
                          const SizedBox(width: HavenSpacing.sm + 2),
                          _buildEmailIconButton(),
                        ],
                      ],
                    ),

                    // Expandable email form
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: _buildEmailForm(),
                      crossFadeState: _showEmailForm
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: HavenMotion.slow,
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
                          style: HavenText.meta,
                        ),
                        GestureDetector(
                          onTap: _toggleMode,
                          child: Text(
                            _isSignUp ? 'Sign in' : 'Sign up',
                            style: const TextStyle(
                              color: HavenColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: HavenSpacing.lg),
                    const Text(
                      'Your Warranties. Protected.',
                      style: HavenText.caption,
                    ),
                    const SizedBox(height: HavenSpacing.xl),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralBanner(String code) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Referral code applied: $code',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md,
          vertical: HavenSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: HavenColors.active.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(HavenRadius.button),
          border: Border.all(
            color: HavenColors.active.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.card_giftcard,
              color: HavenColors.active,
              size: 18,
            ),
            const SizedBox(width: HavenSpacing.sm),
            Flexible(
              child: Text(
                'Referral $code applied',
                style: const TextStyle(
                  color: HavenColors.active,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppleButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HavenRadius.button),
        boxShadow: HavenElevation.glow(Colors.white, strength: 0.18),
      ),
      child: SizedBox(
        height: 54,
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : _signInWithApple,
          icon: const Icon(Icons.apple, size: 22),
          label:
              Text(_isSignUp ? 'Continue with Apple' : 'Sign in with Apple'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HavenRadius.button),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _signInWithGoogle,
        icon: const Text(
          'G',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
          ),
        ),
        label:
            Text(_isSignUp ? 'Continue with Google' : 'Sign in with Google'),
      ),
    );
  }

  /// A compact square outlined button for the email path — pairs beside
  /// the Google button so the auth area stays two rows, not four.
  Widget _buildEmailIconButton() {
    return SizedBox(
      width: 52,
      height: 52,
      child: OutlinedButton(
        onPressed: _isLoading
            ? null
            : () => setState(() => _showEmailForm = true),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HavenRadius.button),
          ),
        ),
        child: const Icon(Icons.email_outlined, size: 20),
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
              maxLength: 128,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: InputDecoration(
                counterText: '',
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
              if (_loginFailed) ...[
                // Prominent forgot password after failed login
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(HavenSpacing.sm),
                  decoration: BoxDecoration(
                    color: HavenColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(HavenRadius.button),
                    border: Border.all(color: HavenColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: GestureDetector(
                    onTap: _openForgotPassword,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_reset, size: 18, color: HavenColors.primary),
                        SizedBox(width: HavenSpacing.xs),
                        Text(
                          'Forgot your password? Reset it here',
                          style: TextStyle(
                            color: HavenColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
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
                        child: HavenLoader(color: Colors.white),
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
