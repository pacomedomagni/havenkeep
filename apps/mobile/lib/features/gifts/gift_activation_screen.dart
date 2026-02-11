import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/services/partners_repository.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/celebration_overlay.dart';

class GiftActivationScreen extends ConsumerStatefulWidget {
  final String giftId;

  const GiftActivationScreen({
    Key? key,
    required this.giftId,
  }) : super(key: key);

  @override
  ConsumerState<GiftActivationScreen> createState() => _GiftActivationScreenState();
}

class _GiftActivationScreenState extends ConsumerState<GiftActivationScreen> {
  late final PartnersRepository _partnersRepo = PartnersRepository(ref.read(apiClientProvider));
  bool _isActivating = false;
  String? _error;
  bool _showCelebration = false;
  int? _premiumMonths;

  @override
  void initState() {
    super.initState();
    _checkAuthAndActivate();
  }

  Future<void> _checkAuthAndActivate() async {
    final authState = ref.read(authProvider);

    if (authState.isAuthenticated) {
      // User is logged in, activate immediately
      await _activateGift();
    } else {
      // User needs to sign up or log in first
      // Store gift ID for after authentication
      // Then navigate to sign up
      // For now, show a message
      if (mounted) {
        setState(() {
          _error = 'Please sign up or log in to activate your gift';
        });
      }
    }
  }

  Future<void> _activateGift() async {
    setState(() {
      _isActivating = true;
      _error = null;
    });

    try {
      final response = await _partnersRepo.activateGift(widget.giftId);

      if (response['success'] == true) {
        final gift = response['data'];
        _premiumMonths = gift['premium_months'] as int?;

        // Show celebration
        setState(() {
          _showCelebration = true;
          _isActivating = false;
        });

        // Wait for celebration animation
        await Future.delayed(const Duration(seconds: 3));

        // Navigate to success screen
        if (mounted) {
          context.go('/gift/activation-success?months=$_premiumMonths');
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to activate gift');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorHandler.getUserMessage(e);
          _isActivating = false;
        });
      }
    }
  }

  void _handleSignUp() {
    // Store gift ID in preferences/storage for after signup
    context.go('/welcome?giftId=${widget.giftId}');
  }

  void _handleLogin() {
    // Store gift ID in preferences/storage for after login
    context.go('/login?giftId=${widget.giftId}');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isActivating) ...[
                    const Center(
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Activating your gift...',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait while we upgrade your account',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ] else if (_error != null) ...[
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: HavenColors.expired,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    if (!authState.isAuthenticated) ...[
                      ElevatedButton(
                        onPressed: _handleSignUp,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Sign Up to Activate',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _handleLogin,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Log In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ] else ...[
                      ElevatedButton(
                        onPressed: _activateGift,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Try Again',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // Celebration overlay
          if (_showCelebration)
            const CelebrationOverlay(
              message: 'Premium Activated!',
            ),
        ],
      ),
    );
  }
}
