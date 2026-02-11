import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/partners_repository.dart';
import '../../core/widgets/havenkeep_logo.dart';

class GiftWelcomeScreen extends StatefulWidget {
  final String giftId;

  const GiftWelcomeScreen({
    Key? key,
    required this.giftId,
  }) : super(key: key);

  @override
  State<GiftWelcomeScreen> createState() => _GiftWelcomeScreenState();
}

class _GiftWelcomeScreenState extends State<GiftWelcomeScreen> {
  final PartnersRepository _partnersRepo = PartnersRepository();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _giftData;

  @override
  void initState() {
    super.initState();
    _loadGiftDetails();
  }

  Future<void> _loadGiftDetails() async {
    try {
      final response = await _partnersRepo.getGiftDetails(widget.giftId);
      if (mounted) {
        setState(() {
          _giftData = response['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _handleActivate() {
    // Navigate to sign up or activation flow
    context.push('/gift/${widget.giftId}/activate');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading your gift...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _giftData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gift Not Found'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'Gift Not Available',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'This gift link may have expired or is invalid.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final gift = _giftData!;
    final brandColor = Color(
      int.parse(gift['brand_color']?.replaceFirst('#', '') ?? 'FF3B82F6', radix: 16) + 0xFF000000,
    );
    final partnerName = gift['partner_name'] ?? 'Your Realtor';
    final logoUrl = gift['logo_url'] as String?;
    final message = gift['custom_message'] as String? ??
        'Welcome to your new home! I\'m excited to share this tool to help you protect your appliances and warranties.';
    final premiumMonths = gift['premium_months'] ?? 6;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              brandColor.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),

                // Partner Logo or HavenKeep Logo
                if (logoUrl != null && logoUrl.isNotEmpty)
                  Center(
                    child: Image.network(
                      logoUrl,
                      height: 80,
                      errorBuilder: (context, error, stackTrace) {
                        return const HavenKeepLogo(size: 80);
                      },
                    ),
                  )
                else
                  const Center(child: HavenKeepLogo(size: 80)),

                const SizedBox(height: 32),

                // Gift Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: brandColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.card_giftcard,
                    size: 64,
                    color: brandColor,
                  ),
                ),

                const SizedBox(height: 24),

                // Title
                Text(
                  'You\'ve Received a Gift!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // From Partner
                Text(
                  'From $partnerName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: brandColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Gift Details Card
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What\'s Included',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildFeatureRow(
                          icon: Icons.stars,
                          color: brandColor,
                          title: '$premiumMonths Months Premium',
                          subtitle: 'Full access to all HavenKeep features',
                        ),
                        const SizedBox(height: 12),

                        _buildFeatureRow(
                          icon: Icons.inventory_2_outlined,
                          color: brandColor,
                          title: 'Unlimited Items',
                          subtitle: 'Track all your home appliances and warranties',
                        ),
                        const SizedBox(height: 12),

                        _buildFeatureRow(
                          icon: Icons.receipt_long,
                          color: brandColor,
                          title: 'Unlimited Documents',
                          subtitle: 'Store receipts, manuals, and warranties',
                        ),
                        const SizedBox(height: 12),

                        _buildFeatureRow(
                          icon: Icons.notifications_active,
                          color: brandColor,
                          title: 'Smart Reminders',
                          subtitle: 'Never miss a warranty expiration',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Personal Message
                if (message.isNotEmpty)
                  Card(
                    elevation: 0,
                    color: brandColor.withOpacity(0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.format_quote,
                                color: brandColor,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Personal Message',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 32),

                // Activate Button
                ElevatedButton(
                  onPressed: _handleActivate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Activate Your Gift',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Learn More
                TextButton(
                  onPressed: () {
                    // Navigate to features/about page
                  },
                  child: Text(
                    'Learn more about HavenKeep',
                    style: TextStyle(color: brandColor),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
