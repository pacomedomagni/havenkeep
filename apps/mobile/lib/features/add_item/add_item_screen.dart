import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

/// Add item screen — method selection bottom sheet (Screen 5.1).
///
/// Methods (in priority order):
/// 1. Quick-Add (~80%) — grid of common appliance categories
/// 2. Scan Receipt (~15%) — camera → OCR → confirm
/// 3. Full Manual Entry (~3%) — all fields
/// 4. Scan Barcode (~2%) — camera → UPC lookup → fill
class AddItemScreen extends ConsumerWidget {
  const AddItemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Add Item'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How would you like to add your item?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // TODO: Quick-Add category grid
              // TODO: Scan Receipt button
              // TODO: Manual Entry button
              // TODO: Scan Barcode button
              const Center(
                child: Text(
                  'Add item methods coming soon',
                  style: TextStyle(color: HavenColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
