import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:confetti/confetti.dart';
import '../../core/widgets/havenkeep_logo.dart';

class GiftActivationSuccessScreen extends StatefulWidget {
  final int premiumMonths;

  const GiftActivationSuccessScreen({
    Key? key,
    this.premiumMonths = 6,
  }) : super(key: key);

  @override
  State<GiftActivationSuccessScreen> createState() =>
      _GiftActivationSuccessScreenState();
}

class _GiftActivationSuccessScreenState
    extends State<GiftActivationSuccessScreen> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _handleGetStarted() {
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final expiryDate = DateTime.now().add(Duration(days: widget.premiumMonths * 30));
    final formattedDate = '${expiryDate.month}/${expiryDate.day}/${expiryDate.year}';

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.1),
                  Colors.white,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),

                    // Success Icon
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle,
                        size: 80,
                        color: Colors.green.shade400,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Success Title
                    Text(
                      'Welcome to Premium!',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Premium Details
                    Text(
                      'Your gift has been activated',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    // Premium Info Card
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.stars,
                                  color: Colors.amber,
                                  size: 32,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${widget.premiumMonths} Months Premium',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Active until $formattedDate',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            // Features List
                            _buildFeatureRow(
                              icon: Icons.inventory_2_outlined,
                              text: 'Track unlimited items',
                            ),
                            const SizedBox(height: 12),
                            _buildFeatureRow(
                              icon: Icons.receipt_long,
                              text: 'Store unlimited documents',
                            ),
                            const SizedBox(height: 12),
                            _buildFeatureRow(
                              icon: Icons.notifications_active,
                              text: 'Smart warranty reminders',
                            ),
                            const SizedBox(height: 12),
                            _buildFeatureRow(
                              icon: Icons.trending_up,
                              text: 'Advanced analytics',
                            ),
                            const SizedBox(height: 12),
                            _buildFeatureRow(
                              icon: Icons.support_agent,
                              text: 'Priority support',
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Get Started Button
                    ElevatedButton(
                      onPressed: _handleGetStarted,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // HavenKeep Logo
                    const Center(
                      child: HavenKeepLogo(size: 40),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Thank you for choosing HavenKeep',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Confetti
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: 1.5708, // Down
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.3,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(
          icon,
          color: Theme.of(context).primaryColor,
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
