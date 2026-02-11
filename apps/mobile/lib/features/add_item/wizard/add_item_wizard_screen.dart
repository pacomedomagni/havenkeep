import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/homes_provider.dart';
import '../../../core/providers/items_provider.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/celebration_overlay.dart';
import 'wizard_step1_basics.dart';
import 'wizard_step2_warranty.dart';
import 'wizard_step3_details.dart';

/// Multi-step wizard for adding items (replaces long 17-field form).
///
/// Step 1: Basics (name, category, brand) - 30 seconds
/// Step 2: Warranty (purchase date, warranty length) - 20 seconds
/// Step 3: Details (optional: price, store, receipt) - 15 seconds
class AddItemWizardScreen extends ConsumerStatefulWidget {
  const AddItemWizardScreen({super.key});

  @override
  ConsumerState<AddItemWizardScreen> createState() => _AddItemWizardScreenState();
}

class _AddItemWizardScreenState extends ConsumerState<AddItemWizardScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;

  // Form data (collected across steps)
  final WizardData _data = WizardData();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      HapticFeedback.lightImpact();
      setState(() {
        _currentStep++;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      HapticFeedback.lightImpact();
      setState(() {
        _currentStep--;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final home = ref.read(currentHomeProvider);
      final user = ref.read(currentUserProvider).value;

      if (home == null || user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No home or user found')),
          );
        }
        return;
      }

      final item = Item(
        id: '',
        homeId: home.id,
        userId: user.id,
        name: _data.name!,
        brand: _data.brand,
        modelNumber: _data.modelNumber,
        serialNumber: _data.serialNumber,
        category: _data.category!,
        room: _data.room,
        purchaseDate: _data.purchaseDate!,
        store: _data.store,
        price: _data.price,
        warrantyMonths: _data.warrantyMonths!,
        warrantyType: _data.warrantyType,
        warrantyProvider: _data.warrantyProvider,
        notes: _data.notes,
        addedVia: ItemAddedVia.manual,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final (newItem, previousCount) = await ref.read(itemsProvider.notifier).addItem(item);

      if (mounted) {
        // Only celebrate the FIRST item - that's truly special
        if (previousCount == 0) {
          CelebrationOverlay.show(
            context,
            type: CelebrationType.firstItem,
            title: '🎉 Great start!',
            subtitle: 'Your first item is protected. Keep adding to build your warranty vault.',
            onDismiss: () {
              context.go('/add-item/success/${newItem.id}');
            },
          );
        } else {
          // Subtle success feedback for subsequent items
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${newItem.name} added successfully'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          context.go('/add-item/success/${newItem.id}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Add Item'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_currentStep > 0)
            TextButton(
              onPressed: _isSaving ? null : _previousStep,
              child: const Text('Back'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgressIndicator(),

          // Page view
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe
              children: [
                WizardStep1Basics(
                  data: _data,
                  onNext: _nextStep,
                ),
                WizardStep2Warranty(
                  data: _data,
                  onNext: _nextStep,
                ),
                WizardStep3Details(
                  data: _data,
                  onSave: _save,
                  isSaving: _isSaving,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          ...List.generate(3, (index) {
            final isCompleted = index < _currentStep;
            final isCurrent = index == _currentStep;

            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: isCompleted || isCurrent
                            ? HavenColors.primary
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (index < 2) const SizedBox(width: 8),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Shared data model for wizard steps.
class WizardData {
  // Step 1: Basics
  String? name;
  ItemCategory? category;
  String? brand;

  // Step 2: Warranty
  DateTime? purchaseDate;
  int? warrantyMonths = 12;
  WarrantyType? warrantyType = WarrantyType.manufacturer;
  String? warrantyProvider;

  // Step 3: Details (optional)
  double? price;
  String? store;
  Room? room;
  String? modelNumber;
  String? serialNumber;
  String? notes;
}
