import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'add_item_wizard_screen.dart';

/// Step 1: Basics (name, category, brand) - ~30 seconds.
class WizardStep1Basics extends StatefulWidget {
  final WizardData data;
  final VoidCallback onNext;

  const WizardStep1Basics({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<WizardStep1Basics> createState() => _WizardStep1BasicsState();
}

class _WizardStep1BasicsState extends State<WizardStep1Basics> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.data.name ?? '';
    _brandController.text = widget.data.brand ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  void _handleNext() {
    if (_formKey.currentState!.validate()) {
      widget.data.name = _nameController.text.trim();
      widget.data.brand = _brandController.text.trim().isNotEmpty
          ? _brandController.text.trim()
          : null;
      widget.onNext();
    }
  }

  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty && widget.data.category != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step title
            const Text(
              'What are you adding?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: HavenColors.textPrimary,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Step 1 of 3',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(height: 32),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                        hintText: 'e.g., Samsung Refrigerator',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a product name';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 24),

                    // Category
                    const Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: HavenColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 12),

                    _buildCategoryGrid(),

                    const SizedBox(height: 24),

                    // Brand (optional)
                    TextFormField(
                      controller: _brandController,
                      decoration: const InputDecoration(
                        labelText: 'Brand (Optional)',
                        hintText: 'e.g., Samsung, Apple',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) {
                        if (_canContinue) _handleNext();
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Continue button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _canContinue ? _handleNext : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final commonCategories = [
      ItemCategory.refrigerator,
      ItemCategory.television,
      ItemCategory.laptop,
      ItemCategory.washingMachine,
      ItemCategory.microwave,
      ItemCategory.dishwasher,
      ItemCategory.smartphone,
      ItemCategory.vacuum,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: commonCategories.map((category) {
        final isSelected = widget.data.category == category;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              widget.data.category = category;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? HavenColors.primary : HavenColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? HavenColors.primary : HavenColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  category.icon,
                  size: 20,
                  color: isSelected ? Colors.white : HavenColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  category.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : HavenColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
