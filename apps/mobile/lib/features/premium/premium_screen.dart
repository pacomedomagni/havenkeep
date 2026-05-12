import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/premium_provider.dart';
import '../../core/router/router.dart';
import '../../core/services/app_prefs_service.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/haven_loader.dart';
import '../../core/widgets/responsive_box.dart';
import '../../main.dart' show environmentConfigProvider;

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _isAnnual = false;
  bool _isSubscribing = false;
  bool _isRestoring = false;

  /// Future for the live RevenueCat offering. Resolved once on first
  /// build so we can render real `priceString` values instead of the
  /// previously hardcoded "$2.99/month" / "$24/year" strings.
  late final Future<Offering?> _offeringFuture;

  @override
  void initState() {
    super.initState();
    _offeringFuture = ref.read(premiumServiceProvider).getActiveOffering();
  }

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
            // Deep-link to the OS-owned subscription page so users can
            // cancel / change plans through the App Store / Play Store.
            // Apple + Google both require this entry point in apps that
            // sell subscriptions.
            if (manageSubscriptionSupported)
              OutlinedButton.icon(
                onPressed: () => AppPrefsService.openManageSubscription(),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Manage Subscription'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HavenColors.primary,
                  side: const BorderSide(color: HavenColors.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: HavenSpacing.xl,
                    vertical: HavenSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(HavenRadius.chip),
                  ),
                ),
              ),
            const SizedBox(height: HavenSpacing.md),
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
            const SizedBox(height: HavenSpacing.lg),
            _buildLegalLinks(),
          ],
        ),
      ),
    );
  }

  /// Render the Privacy / Terms link row required by App Store + Play
  /// Store review for any screen that pitches a subscription.
  Widget _buildLegalLinks() {
    final config = ref.watch(environmentConfigProvider);
    Future<void> open(String path) async {
      final uri = Uri.parse('${config.appUrl}$path');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: HavenSpacing.md,
      runSpacing: HavenSpacing.xs,
      children: [
        TextButton(
          onPressed: () => open('/privacy'),
          child: const Text(
            'Privacy Policy',
            style: TextStyle(color: HavenColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => open('/terms'),
          child: const Text(
            'Terms of Service',
            style: TextStyle(color: HavenColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildUpgradeContent() {
    return ResponsiveBox(
      maxWidth: 560,
      child: SingleChildScrollView(
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
          const SizedBox(height: HavenSpacing.md),
          _buildLegalLinks(),
          const SizedBox(height: HavenSpacing.lg),
        ],
      ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return HavenCard.highlight(
      width: double.infinity,
      glow: HavenColors.primary,
      padding: const EdgeInsets.symmetric(
          vertical: HavenSpacing.xl, horizontal: HavenSpacing.lg),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                size: 36, color: Colors.white),
          ),
          const SizedBox(height: HavenSpacing.md),
          Text('HavenKeep Premium',
              style: HavenText.displayMedium.copyWith(color: Colors.white)),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            'Unlimited items, smart capture, PDF export, priority support.',
            textAlign: TextAlign.center,
            style: HavenText.bodySecondary
                .copyWith(color: Colors.white.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureComparison() {
    return Column(
      children: [
        _buildComparisonCard(
          title: 'Free',
          features: const [
            _FeatureItem(Icons.inventory_2, '5 items', false),
            _FeatureItem(Icons.category, 'Basic categories', false),
            _FeatureItem(Icons.edit, 'Manual entry only', false),
          ],
          isFree: true,
        ),
        const SizedBox(height: HavenSpacing.md),
        _buildComparisonCard(
          title: 'Premium',
          features: const [
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
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: HavenText.titleLarge.copyWith(
                color: isFree ? HavenColors.textSecondary : HavenColors.gold,
              ),
            ),
            if (!isFree) ...[
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: HavenColors.gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(HavenRadius.pill),
                ),
                child: Text('RECOMMENDED',
                    style: HavenText.badge.copyWith(color: HavenColors.gold)),
              ),
            ],
          ],
        ),
        const SizedBox(height: HavenSpacing.md),
        ...features.map((feature) => _buildFeatureRow(feature, isFree)),
      ],
    );

    if (isFree) {
      return HavenCard.flat(width: double.infinity, child: card);
    }
    return HavenCard(
      width: double.infinity,
      borderColor: HavenColors.gold.withValues(alpha: 0.45),
      glow: HavenColors.gold,
      child: card,
    );
  }

  Widget _buildFeatureRow(_FeatureItem feature, bool isFree) {
    final available = feature.isPremium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(feature.icon, size: 18, color: HavenColors.textTertiary),
          const SizedBox(width: HavenSpacing.sm + 2),
          Expanded(
            child: Text(feature.text,
                style: HavenText.body.copyWith(
                    color: available
                        ? HavenColors.textPrimary
                        : HavenColors.textSecondary)),
          ),
          Icon(
            available ? Icons.check_circle : Icons.remove_circle_outline,
            size: 18,
            color: available
                ? HavenColors.active
                : HavenColors.textTertiary,
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
                    activeThumbColor: HavenColors.gold,
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
          FutureBuilder<Offering?>(
            future: _offeringFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 44,
                  child: HavenLoader(color: HavenColors.textTertiary),
                );
              }
              final offering = snapshot.data;
              if (offering == null) {
                return const Text(
                  'Pricing unavailable',
                  style: TextStyle(
                    fontSize: 16,
                    color: HavenColors.textTertiary,
                  ),
                );
              }
              final monthly = offering.monthly;
              final annual = offering.annual;
              final selected = _isAnnual ? annual : monthly;
              if (selected == null) {
                return const Text(
                  'Plan unavailable',
                  style: TextStyle(
                    fontSize: 16,
                    color: HavenColors.textTertiary,
                  ),
                );
              }
              return Column(
                children: [
                  Text(
                    selected.storeProduct.priceString,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  if (_isAnnual && annual != null && monthly != null)
                    _buildAnnualSavings(annual, monthly),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Compute the % savings of the annual plan over 12x the monthly plan
  /// using the RevenueCat numeric prices, and render the badge.
  Widget _buildAnnualSavings(Package annual, Package monthly) {
    final monthlyPrice = monthly.storeProduct.price;
    final annualPrice = annual.storeProduct.price;
    if (monthlyPrice <= 0 || annualPrice <= 0) {
      return const SizedBox.shrink();
    }
    final twelveMonths = monthlyPrice * 12;
    if (annualPrice >= twelveMonths) {
      return const SizedBox.shrink();
    }
    final pctSaved = (((twelveMonths - annualPrice) / twelveMonths) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: HavenSpacing.sm),
      child: Text(
        'Save $pctSaved%',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: HavenColors.active,
        ),
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
                child: HavenLoader(color: HavenColors.background),
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
              child: HavenLoader(color: HavenColors.textSecondary),
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
