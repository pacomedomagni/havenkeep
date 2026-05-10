import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/price_parser.dart';
import '../../core/widgets/celebration_overlay.dart';
import '../../core/widgets/haven_loader.dart';
import '../../core/utils/haven_haptics.dart';
import 'add_item_guard.dart';

/// Quick-Add form screen for a specific category.
///
/// Pre-fills defaults from category_defaults and collects minimal info:
/// brand, purchase date, warranty duration, and room.
class QuickAddScreen extends ConsumerStatefulWidget {
  final ItemCategory category;

  const QuickAddScreen({super.key, required this.category});

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  final _formKey = GlobalKey<FormState>();

  ItemCategory get _category => widget.category;

  String _brand = '';
  DateTime? _purchaseDate;
  int _warrantyMonths = 12;
  ItemRoom? _selectedRoom;
  bool _defaultsApplied = false;
  bool _showMoreDetails = false;
  bool _isSaving = false;

  // Optional fields
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  final _priceController = TextEditingController();
  final _storeController = TextEditingController();

  @override
  void dispose() {
    _modelController.dispose();
    _serialController.dispose();
    _priceController.dispose();
    _storeController.dispose();
    super.dispose();
  }

  bool get _isFormValid =>
      // Trim before checking so trailing whitespace doesn't satisfy the
      // brand requirement (Ch05-F019).
      _brand.trim().isNotEmpty && _purchaseDate != null;

  Future<void> _pickDate() async {
    HavenHaptics.tap();
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
        // Local midnight (Ch05-F005).
        _purchaseDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || !_isFormValid) return;

    HavenHaptics.confirm();
    setState(() => _isSaving = true);

    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to add items.')),
          );
        }
        return;
      }

      final home = ref.read(currentHomeProvider);
      if (home == null) {
        if (mounted) context.go('/home-setup');
        return;
      }

      // Use the locale-aware price parser so "1,99" doesn't silently drop
      // (Ch05-F009).
      final price = _priceController.text.isNotEmpty
          ? parsePriceInput(_priceController.text)
          : null;

      // Ch05-F019: trim before persisting so trailing whitespace from
      // the autocomplete field doesn't fork the brand index.
      final brand = _brand.trim();

      final item = Item(
        // H53: client-side UUID (see manual_entry_screen H53 comment).
        id: const Uuid().v4(),
        homeId: home.id,
        userId: user.id,
        name: _category.displayLabel,
        brand: brand.isNotEmpty ? brand : null,
        modelNumber: _modelController.text.trim().isNotEmpty
            ? _modelController.text.trim()
            : null,
        serialNumber: _serialController.text.trim().isNotEmpty
            ? _serialController.text.trim()
            : null,
        category: _category,
        room: _selectedRoom,
        purchaseDate: _purchaseDate!,
        store:
            _storeController.text.trim().isNotEmpty ? _storeController.text.trim() : null,
        price: price,
        warrantyMonths: _warrantyMonths,
        // Mirror the server formula (Ch08-Item-D010) so the new item's
        // expiry preview lines up with the row we'll get back.
        warrantyEndDate:
            Item.computeWarrantyEndDate(_purchaseDate!, _warrantyMonths),
        addedVia: ItemAddedVia.quick_add,
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
              context.go('/add-item/success/${newItem.id}', extra: newItem);
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
          context.go('/add-item/success/${newItem.id}', extra: newItem);
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
    final brandsAsync = ref.watch(brandSuggestionsProvider(_category));

    // Apply category defaults via ref.listen so we never mutate state inside
    // build() (Ch05-F017). The listener fires once when the provider's data
    // arrives — guarded by `_defaultsApplied` so subsequent rebuilds don't
    // overwrite user choices.
    ref.listen<AsyncValue<List<CategoryDefault>>>(categoryDefaultsProvider,
        (previous, next) {
      if (_defaultsApplied) return;
      next.whenData((defaults) {
        final match = defaults.where((d) => d.category == _category).toList();
        if (match.isEmpty) return;
        _defaultsApplied = true;
        if (!mounted) return;
        setState(() {
          _selectedRoom = match.first.defaultRoom;
          _warrantyMonths = match.first.warrantyMonths;
        });
      });
    });

    // Initial sync read in case the provider already has data on the first
    // build (covers hot-restart and cached values).
    if (!_defaultsApplied) {
      final defaults = ref
          .read(categoryDefaultsProvider)
          .whenOrNull(data: (d) => d) ??
          const <CategoryDefault>[];
      final match = defaults.where((d) => d.category == _category).toList();
      if (match.isNotEmpty) {
        _defaultsApplied = true;
        _selectedRoom = match.first.defaultRoom;
        _warrantyMonths = match.first.warrantyMonths;
      }
    }

    // H57: gate every direct add-item route on the free-plan limit.
    return AddItemGuard(child: Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: Text(
          'Add ${_category.displayLabel}',
          style: const TextStyle(fontWeight: FontWeight.bold),
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
                // Category icon
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: HavenColors.surface,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: CategoryIcon.widget(_category, size: 64),
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),

                // Brand field (required)
                BrandAutocompleteField(
                  brands: brandsAsync.value ?? [],
                  onChanged: (value) {
                    setState(() {
                      _brand = value;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Brand is required';
                    }
                    return null;
                  },
                  label: 'Brand *',
                ),
                const SizedBox(height: HavenSpacing.md),

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

                // Warranty Duration
                const Text(
                  'Warranty Duration',
                  style: TextStyle(
                    fontSize: 13,
                    color: HavenColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                // Re-key on _defaultsApplied so the picker rebuilds with the
                // post-default value once category defaults arrive
                // (Ch05-F018).
                WarrantyDurationPicker(
                  key: ValueKey('warranty-$_defaultsApplied-$_warrantyMonths'),
                  initialMonths: _warrantyMonths,
                  onChanged: (months) {
                    setState(() {
                      _warrantyMonths = months;
                    });
                  },
                ),
                const SizedBox(height: HavenSpacing.md),

                // Room info
                Container(
                  padding: const EdgeInsets.all(HavenSpacing.md),
                  decoration: BoxDecoration(
                    color: HavenColors.surface,
                    borderRadius: BorderRadius.circular(HavenRadius.input),
                    border: Border.all(color: HavenColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Saving to: ${_selectedRoom?.displayLabel ?? 'None'}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: HavenColors.textSecondary,
                          ),
                        ),
                      ),
                      Semantics(
                        label: 'Change room',
                        child: TextButton(
                          onPressed: () async {
                            HavenHaptics.tap();
                            await showDialog<ItemRoom?>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: HavenColors.elevated,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      HavenRadius.card),
                                ),
                                title: const Text('Select Room'),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  child: RoomPicker(
                                    value: _selectedRoom,
                                    onChanged: (room) {
                                      setState(() {
                                        _selectedRoom = room;
                                      });
                                      Navigator.of(ctx).pop();
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'change',
                            style: TextStyle(
                              color: HavenColors.secondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),

                // Save button
                ElevatedButton(
                  onPressed: _isFormValid && !_isSaving ? _save : null,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: HavenLoader(color: HavenColors.textPrimary),
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

                // Expandable "more details" section
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showMoreDetails = !_showMoreDetails;
                    });
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Want to add more details?',
                        style: TextStyle(
                          fontSize: 13,
                          color: HavenColors.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: HavenSpacing.xs),
                      Icon(
                        _showMoreDetails
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: HavenColors.secondary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),

                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    children: [
                      const SizedBox(height: HavenSpacing.sm),
                      TextFormField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'Model Number',
                        ),
                      ),
                      const SizedBox(height: HavenSpacing.md),
                      TextFormField(
                        controller: _serialController,
                        decoration: const InputDecoration(
                          labelText: 'Serial Number',
                        ),
                      ),
                      const SizedBox(height: HavenSpacing.md),
                      TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price Paid',
                          prefixText: '\$ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        // Block negative signs and non-numeric paste; cap
                        // length so a paste-bomb can't crash decode
                        // (Ch05 NaN guard).
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]'),
                          ),
                          LengthLimitingTextInputFormatter(12),
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final parsed = parsePriceInput(value);
                          if (parsed == null) return 'Enter a valid price';
                          if (parsed < 0) return 'Price cannot be negative';
                          if (parsed > 1000000) return 'Price seems too high';
                          return null;
                        },
                      ),
                      const SizedBox(height: HavenSpacing.md),
                      TextFormField(
                        controller: _storeController,
                        decoration: const InputDecoration(
                          labelText: 'Store / Retailer',
                        ),
                      ),
                      const SizedBox(height: HavenSpacing.lg),
                    ],
                  ),
                  crossFadeState: _showMoreDetails
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
