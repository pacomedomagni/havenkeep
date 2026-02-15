import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/celebration_overlay.dart';

/// Full manual entry form for adding an item with all fields.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  // Required fields
  final _nameController = TextEditingController();
  DateTime? _purchaseDate;
  int _warrantyMonths = 12;

  // Optional fields
  String _brand = '';
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  ItemCategory _category = ItemCategory.other;
  ItemRoom? _selectedRoom;
  final _storeController = TextEditingController();
  final _priceController = TextEditingController();
  WarrantyType _warrantyType = WarrantyType.manufacturer;
  final _warrantyProviderController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _storeController.dispose();
    _priceController.dispose();
    _warrantyProviderController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty && _purchaseDate != null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(1970),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: HavenColors.primary,
              onPrimary: HavenColors.textPrimary,
              surface: HavenColors.elevated,
              onSurface: HavenColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _purchaseDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || !_isFormValid) return;

    setState(() => _isSaving = true);

    try {
      final home = ref.read(currentHomeProvider);
      final user = ref.read(currentUserProvider).value;

      if (home == null || user == null) {
        if (mounted) {
          showHavenSnackBar(context, message: 'Error: No home or user found', isError: true);
        }
        return;
      }

      final price = _priceController.text.isNotEmpty
          ? double.tryParse(_priceController.text)
          : null;

      final item = Item(
        id: '',
        homeId: home.id,
        userId: user.id,
        name: _nameController.text.trim(),
        brand: _brand.isNotEmpty ? _brand : null,
        modelNumber: _modelController.text.isNotEmpty
            ? _modelController.text.trim()
            : null,
        serialNumber: _serialController.text.isNotEmpty
            ? _serialController.text.trim()
            : null,
        category: _category,
        room: _selectedRoom,
        purchaseDate: _purchaseDate!,
        store: _storeController.text.isNotEmpty
            ? _storeController.text.trim()
            : null,
        price: price,
        warrantyMonths: _warrantyMonths,
        warrantyType: _warrantyType,
        warrantyProvider: _warrantyProviderController.text.isNotEmpty
            ? _warrantyProviderController.text.trim()
            : null,
        notes: _notesController.text.isNotEmpty
            ? _notesController.text.trim()
            : null,
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
              backgroundColor: HavenColors.active,
            ),
          );
          context.go('/add-item/success/${newItem.id}');
        }
      }
    } catch (e) {
      if (mounted) {
        showHavenSnackBar(context, message: ErrorHandler.getUserMessage(e), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildSectionDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HavenSpacing.lg),
      child: Row(
        children: [
          const Expanded(child: Divider(color: HavenColors.border)),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: HavenSpacing.md),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: HavenColors.textTertiary,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const Expanded(child: Divider(color: HavenColors.border)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brandsAsync = ref.watch(brandSuggestionsProvider(_category));

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text(
          'Add Item',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _FormProgressBar(
            purchaseDate: _purchaseDate,
            nameIsNotEmpty: _nameController.text.trim().isNotEmpty,
            warrantyMonths: _warrantyMonths,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Product Name (required)
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Product name is required';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Brand
                BrandAutocompleteField(
                  brands: brandsAsync.value ?? [],
                  onChanged: (value) {
                    setState(() {
                      _brand = value;
                    });
                  },
                  label: 'Brand',
                ),
                const SizedBox(height: HavenSpacing.md),

                // Model Number
                TextFormField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model Number',
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Serial Number
                TextFormField(
                  controller: _serialController,
                  decoration: const InputDecoration(
                    labelText: 'Serial Number (optional)',
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Category
                DropdownButtonFormField<ItemCategory>(
                  value: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                  ),
                  dropdownColor: HavenColors.elevated,
                  items: ItemCategory.values
                      .map(
                        (cat) => DropdownMenuItem<ItemCategory>(
                          value: cat,
                          child: Text(cat.displayLabel),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _category = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: HavenSpacing.md),

                // Room
                RoomPicker(
                  value: _selectedRoom,
                  onChanged: (room) {
                    setState(() {
                      _selectedRoom = room;
                    });
                  },
                ),

                // Purchase Info section
                _buildSectionDivider('PURCHASE INFO'),

                // Purchase Date (required)
                GestureDetector(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Purchase Date *',
                      suffixIcon: const Icon(
                        Icons.calendar_today,
                        color: HavenColors.textTertiary,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: HavenColors.surface,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.input),
                        borderSide:
                            const BorderSide(color: HavenColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.input),
                        borderSide:
                            const BorderSide(color: HavenColors.border),
                      ),
                    ),
                    child: Text(
                      _purchaseDate != null
                          ? DateFormat('MMM d, yyyy').format(_purchaseDate!)
                          : 'Select date',
                      style: TextStyle(
                        color: _purchaseDate != null
                            ? HavenColors.textPrimary
                            : HavenColors.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Store / Retailer
                TextFormField(
                  controller: _storeController,
                  decoration: const InputDecoration(
                    labelText: 'Store / Retailer',
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Price Paid
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: 'Price Paid',
                    prefixText: '\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final parsed = double.tryParse(value);
                    if (parsed == null) {
                      return 'Enter a valid number';
                    }
                    if (parsed < 0) {
                      return 'Price cannot be negative';
                    }
                    return null;
                  },
                ),

                // Warranty Info section
                _buildSectionDivider('WARRANTY INFO'),

                // Warranty Duration (required)
                const Text(
                  'Warranty Duration *',
                  style: TextStyle(
                    fontSize: 13,
                    color: HavenColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                WarrantyDurationPicker(
                  initialMonths: _warrantyMonths,
                  onChanged: (months) {
                    setState(() {
                      _warrantyMonths = months;
                    });
                  },
                ),
                const SizedBox(height: HavenSpacing.md),

                // Warranty Type (choice chips)
                const Text(
                  'Warranty Type',
                  style: TextStyle(
                    fontSize: 13,
                    color: HavenColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                Wrap(
                  spacing: HavenSpacing.sm,
                  children: [
                    WarrantyType.manufacturer,
                    WarrantyType.extended,
                    WarrantyType.store,
                  ].map((type) {
                    final isSelected = _warrantyType == type;
                    return ChoiceChip(
                      label: Text(type.displayLabel),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _warrantyType = type;
                          });
                        }
                      },
                      selectedColor: HavenColors.primary,
                      backgroundColor: HavenColors.surface,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? HavenColors.textPrimary
                            : HavenColors.textSecondary,
                        fontSize: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.chip),
                        side: BorderSide(
                          color: isSelected
                              ? HavenColors.primary
                              : HavenColors.border,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: HavenSpacing.md),

                // Warranty Provider
                TextFormField(
                  controller: _warrantyProviderController,
                  decoration: const InputDecoration(
                    labelText: 'Warranty Provider',
                  ),
                ),

                // Notes section
                _buildSectionDivider('NOTES'),

                // Notes
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: HavenSpacing.xl),

                // Save button
                ElevatedButton(
                  onPressed: _isFormValid && !_isSaving ? _save : null,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: HavenColors.textPrimary,
                          ),
                        )
                      : const Text(
                          'Save Item',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: HavenSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin progress bar showing how much of the form is completed.
class _FormProgressBar extends StatelessWidget {
  final DateTime? purchaseDate;
  final bool nameIsNotEmpty;
  final int warrantyMonths;

  const _FormProgressBar({
    required this.purchaseDate,
    required this.nameIsNotEmpty,
    required this.warrantyMonths,
  });

  @override
  Widget build(BuildContext context) {
    // 3 required sections: product info, purchase info, warranty info
    int completed = 0;
    if (nameIsNotEmpty) completed++;
    if (purchaseDate != null) completed++;
    if (warrantyMonths > 0) completed++; // always true by default, counts as done

    final progress = completed / 3;

    return LinearProgressIndicator(
      value: progress,
      backgroundColor: HavenColors.surface,
      valueColor: AlwaysStoppedAnimation<Color>(
        progress >= 1.0 ? HavenColors.active : HavenColors.primary,
      ),
      minHeight: 4,
    );
  }
}
