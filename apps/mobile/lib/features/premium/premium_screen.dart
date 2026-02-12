import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/premium_provider.dart';
import '../../core/router/router.dart';
import '../../core/utils/error_handler.dart';

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _isAnnual = false;
  bool _isSubscribing = false;
  bool _isRestoring = false;

  Future<void> _subscribe() async {
    setState(() => _isSubscribing = true);
    try {
      await ref.read(premiumServiceProvider).subscribeToPremium(
            plan: _isAnnual ? 'annual' : 'monthly',
          );
      if (mounted) {
        context.go(AppRoutes.premiumSuccess);
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
      if (mounted) {
        setState(() => _isSubscribing = false);
      }
    }
  }

  Future<void> _restorePurchase() async {
    setState(() => _isRestoring = true);
    try {
      await ref.read(premiumServiceProvider).restorePurchase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase restored successfully!'),
            backgroundColor: HavenColors.active,
          ),
        );
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
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Upgrade to Premium'),
        backgroundColor: HavenColors.background,
        foregroundColor: HavenColors.textPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: isPremium
          ? _buildAlreadyPremium()
          : _buildUpgradeContent(),
    );
  }

  Widget _buildAlreadyPremium() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HavenSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.star,
              size: 80,
              color: HavenColors.gold,
            ),
            const SizedBox(height: HavenSpacing.lg),
            const Text(
              "You're already on Premium!",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: HavenColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HavenSpacing.md),
            const Text(
              'Enjoy unlimited items and all premium features.',
              style: TextStyle(
                fontSize: 16,
                color: HavenColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HavenSpacing.xl),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: HavenColors.primary,
                foregroundColor: HavenColors.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: HavenSpacing.xl,
                  vertical: HavenSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HavenRadius.chip),
                ),
              ),
              child: const Text(
                'Go Back',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HavenSpacing.lg),
      child: Column(
        children: [
          _buildHeroSection(),
          const SizedBox(height: HavenSpacing.xl),
          _buildFeatureComparison(),
          const SizedBox(height: HavenSpacing.xl),
          _buildPricingToggle(),
          const SizedBox(height: HavenSpacing.lg),
          _buildSubscribeButton(),
          const SizedBox(height: HavenSpacing.md),
          _buildRestoreButton(),
          const SizedBox(height: HavenSpacing.md),
          const Text(
            'Subscription auto-renews. Cancel anytime in your device settings.',
            style: TextStyle(
              fontSize: 12,
              color: HavenColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HavenSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Column(
      children: const [
        Icon(
          Icons.star,
          size: 80,
          color: HavenColors.gold,
        ),
        SizedBox(height: HavenSpacing.md),
        Text(
          'Unlock HavenKeep Premium',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: HavenColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFeatureComparison() {
    return Column(
      children: [
        _buildComparisonCard(
          title: 'Free',
          features: [
            _FeatureItem(Icons.inventory_2, '5 items', false),
            _FeatureItem(Icons.category, 'Basic categories', false),
            _FeatureItem(Icons.edit, 'Manual entry only', false),
          ],
          isFree: true,
        ),
        const SizedBox(height: HavenSpacing.md),
        _buildComparisonCard(
          title: 'Premium',
          features: [
            _FeatureItem(Icons.all_inclusive, 'Unlimited items', true),
            _FeatureItem(Icons.category, 'All categories', true),
            _FeatureItem(Icons.qr_code_scanner, 'Receipt & barcode scanning', true),
            _FeatureItem(Icons.picture_as_pdf, 'PDF export', true),
            _FeatureItem(Icons.support_agent, 'Priority support', true),
          ],
          isFree: false,
        ),
      ],
    );
  }

  Widget _buildComparisonCard({
    required String title,
    required List<_FeatureItem> features,
    required bool isFree,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HavenSpacing.lg),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(
          color: isFree ? HavenColors.border : HavenColors.gold,
          width: isFree ? 1 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isFree ? HavenColors.textPrimary : HavenColors.gold,
            ),
          ),
          const SizedBox(height: HavenSpacing.md),
          ...features.map((feature) => _buildFeatureRow(feature, isFree)),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(_FeatureItem feature, bool isFree) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm / 2),
      child: Row(
        children: [
          Icon(
            feature.icon,
            size: 20,
            color: HavenColors.textSecondary,
          ),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Text(
              feature.text,
              style: const TextStyle(
                fontSize: 14,
                color: HavenColors.textSecondary,
              ),
            ),
          ),
          Icon(
            feature.isPremium ? Icons.check_circle : Icons.cancel,
            size: 20,
            color: feature.isPremium ? HavenColors.active : HavenColors.expired,
          ),
        ],
      ),
    );
  }

  Widget _buildPricingToggle() {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.lg),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        children: [
          MergeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Monthly',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: !_isAnnual
                        ? HavenColors.textPrimary
                        : HavenColors.textTertiary,
                  ),
                ),
                const SizedBox(width: HavenSpacing.sm),
                Semantics(
                  label: 'Switch between monthly and annual billing',
                  child: Switch(
                    value: _isAnnual,
                    onChanged: (value) => setState(() => _isAnnual = value),
                    activeColor: HavenColors.gold,
                    inactiveThumbColor: HavenColors.primary,
                    inactiveTrackColor: HavenColors.elevated,
                  ),
                ),
                const SizedBox(width: HavenSpacing.sm),
                Text(
                  'Annual',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _isAnnual
                        ? HavenColors.textPrimary
                        : HavenColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HavenSpacing.md),
          Text(
            _isAnnual ? '\$24/year' : '\$2.99/month',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: HavenColors.textPrimary,
            ),
          ),
          if (_isAnnual)
            const Padding(
              padding: EdgeInsets.only(top: HavenSpacing.sm),
              child: Text(
                'Save 33%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: HavenColors.active,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscribeButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubscribing ? null : _subscribe,
        style: ElevatedButton.styleFrom(
          backgroundColor: HavenColors.gold,
          foregroundColor: HavenColors.background,
          padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HavenRadius.chip),
          ),
          disabledBackgroundColor: HavenColors.gold.withValues(alpha: 0.5),
        ),
        child: _isSubscribing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: HavenColors.background,
                ),
              )
            : const Text(
                'Subscribe',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildRestoreButton() {
    return TextButton(
      onPressed: _isRestoring ? null : _restorePurchase,
      child: _isRestoring
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HavenColors.textSecondary,
              ),
            )
          : const Text(
              'Restore Purchase',
              style: TextStyle(
                fontSize: 14,
                color: HavenColors.textSecondary,
                decoration: TextDecoration.underline,
              ),
            ),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String text;
  final bool isPremium;

  const _FeatureItem(this.icon, this.text, this.isPremium);
}
