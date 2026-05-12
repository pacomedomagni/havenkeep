import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/services/partners_repository.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/celebration_overlay.dart';
import '../../core/widgets/haven_loader.dart';

/// Activation screen reached via deep link `havenkeep://gift/<code>` (or the
/// Universal Link `https://havenkeep.com/gift/<code>`). Pre-fills the code
/// the user shared and asks for the homebuyer email — both are required by
/// the backend `verify-code` endpoint to close the enumeration oracle. After
/// a successful verify the screen calls `activate` with the resolved gift id
/// and animates to the success screen.
///
/// Unauthenticated visitors see a sign-in prompt. The pending gift code is
/// stashed in SharedPreferences under [pendingGiftCodeKey] so the welcome
/// screen can pick it up after sign-up — mirrors the existing
/// `pending referral` pattern.
class GiftActivationScreen extends ConsumerStatefulWidget {
  /// Activation code copied straight out of the deep link path. The user
  /// can edit it in the field — pasting from a partner email is the most
  /// common alternative entry path.
  final String code;

  const GiftActivationScreen({
    super.key,
    required this.code,
  });

  /// SharedPreferences key for an unauthenticated visitor's pending gift
  /// code. Cleared once the welcome screen consumes it post-signup.
  static const String pendingGiftCodeKey = 'pending_gift_code';

  @override
  ConsumerState<GiftActivationScreen> createState() =>
      _GiftActivationScreenState();
}

class _GiftActivationScreenState extends ConsumerState<GiftActivationScreen> {
  late final PartnersRepository _partnersRepo =
      PartnersRepository(ref.read(apiClientProvider));
  late final TextEditingController _codeController;
  late final TextEditingController _emailController;

  bool _isActivating = false;
  String? _error;
  bool _showCelebration = false;
  int _premiumMonths = 6;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.code);
    _emailController = TextEditingController();
    _stashCodeIfUnauthenticated();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Persist the deep-link code while unauthenticated so the welcome screen
  /// can resume the flow once sign-up completes (pending-referral pattern).
  Future<void> _stashCodeIfUnauthenticated() async {
    final isAuthenticated = ref.read(isAuthenticatedProvider);
    if (isAuthenticated) return;
    final code = widget.code.trim();
    if (code.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GiftActivationScreen.pendingGiftCodeKey, code);
  }

  Future<void> _activate() async {
    final code = _codeController.text.trim();
    final email = _emailController.text.trim();

    if (code.isEmpty) {
      setState(() => _error = 'Activation code is required');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter the email this gift was sent to');
      return;
    }

    setState(() {
      _isActivating = true;
      _error = null;
    });

    try {
      // Step 1: verify the code + email pair to resolve the gift id.
      final verifyResponse = await _partnersRepo.verifyActivationCode(
        code: code,
        homebuyerEmail: email,
      );
      final verifyData = verifyResponse['data'] as Map<String, dynamic>?;
      final giftId = verifyData?['gift_id'] as String?;
      if (giftId == null || giftId.isEmpty) {
        throw Exception('Invalid activation code or email');
      }

      // Step 2: activate the resolved gift.
      final activateResponse = await _partnersRepo.activateGift(giftId);
      if (activateResponse['success'] != true) {
        throw Exception(
          activateResponse['message'] ?? 'Failed to activate gift',
        );
      }

      final gift = activateResponse['data'] as Map<String, dynamic>?;
      final rawMonths = gift?['premium_months'];
      if (rawMonths is num) {
        _premiumMonths = rawMonths.toInt();
      }

      // Successful activation — wipe any stashed deep-link code so a later
      // resume can't rerun the flow.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(GiftActivationScreen.pendingGiftCodeKey);

      // C4: force a fresh /users/me read so isPremiumProvider re-derives
      // from the now-updated user.plan. Without this, the success screen +
      // any subsequent navigation reads stale data (10s user-cache TTL)
      // and renders "free plan" until the cache expires.
      ref.invalidate(currentUserProvider);

      if (!mounted) return;
      setState(() {
        _showCelebration = true;
        _isActivating = false;
      });

      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      context.go('/gift/activation-success?months=$_premiumMonths');
    } catch (e) {
      // C5: clear the stashed code on FAILURE too. The error path used to
      // leave the code in prefs, which meant a network-blip retry would
      // auto-resume the same code on cold start, and a logout-then-login
      // flow on a shared device let user B inherit user A's pending code.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(GiftActivationScreen.pendingGiftCodeKey);
      } catch (_) {
        // ignore — best-effort cleanup
      }
      if (mounted) {
        setState(() {
          _error = ErrorHandler.getUserMessage(e);
          _isActivating = false;
        });
      }
    }
  }

  void _handleSignUp() {
    // Welcome screen handles both sign-up and sign-in, and reads the
    // pending gift code from prefs once the user authenticates.
    context.go('/welcome?pendingGift=${Uri.encodeComponent(widget.code)}');
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Activate Gift')),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(HavenSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: HavenSpacing.lg),
                  const Center(
                    child: Icon(
                      Icons.card_giftcard,
                      size: 72,
                      color: HavenColors.primary,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.lg),
                  Text(
                    'You have a HavenKeep gift',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: HavenColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  const Text(
                    'Enter the email your gift was sent to and we will '
                    'activate your premium months.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: HavenColors.textSecondary),
                  ),
                  const SizedBox(height: HavenSpacing.xl),

                  if (!isAuthenticated) ...[
                    _SignInPrompt(onSignIn: _handleSignUp),
                    const SizedBox(height: HavenSpacing.lg),
                  ],

                  TextField(
                    controller: _codeController,
                    enabled: !_isActivating && isAuthenticated,
                    decoration: InputDecoration(
                      labelText: 'Activation code',
                      filled: true,
                      fillColor: HavenColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(HavenRadius.card),
                      ),
                    ),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(32),
                    ],
                    style: const TextStyle(
                      color: HavenColors.textPrimary,
                      letterSpacing: 1.2,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: HavenSpacing.md),
                  TextField(
                    controller: _emailController,
                    enabled: !_isActivating && isAuthenticated,
                    decoration: InputDecoration(
                      labelText: 'Email this gift was sent to',
                      filled: true,
                      fillColor: HavenColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(HavenRadius.card),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: const TextStyle(color: HavenColors.textPrimary),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: HavenSpacing.md),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: HavenColors.expired,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: HavenSpacing.xl),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_isActivating || !isAuthenticated)
                          ? null
                          : _activate,
                      child: _isActivating
                          ? const HavenLoader()
                          : const Text(
                              'Activate Gift',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.xxl),
                ],
              ),
            ),
          ),

          if (_showCelebration)
            const CelebrationOverlay(
              type: CelebrationType.itemAdded,
              title: 'Premium Activated!',
              subtitle: 'Enjoy your premium features.',
            ),
        ],
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  final VoidCallback onSignIn;
  const _SignInPrompt({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(
          color: HavenColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Sign in to activate your gift',
            style: TextStyle(
              color: HavenColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),
          const Text(
            "We'll resume right here once you're signed in.",
            textAlign: TextAlign.center,
            style: TextStyle(color: HavenColors.textSecondary),
          ),
          const SizedBox(height: HavenSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSignIn,
              child: const Text('Sign in / sign up'),
            ),
          ),
        ],
      ),
    );
  }
}
