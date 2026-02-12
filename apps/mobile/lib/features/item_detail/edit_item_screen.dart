import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/error_state_widget.dart';

/// Edit item form screen. Mirrors the manual entry layout but pre-fills all
/// fields from the existing item and supports dirty-state tracking.
class EditItemScreen extends ConsumerStatefulWidget {
  final String itemId;

  const EditItemScreen({super.key, required this.itemId});

  @override
  ConsumerState<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends ConsumerState<EditItemScreen> {
  final _formKey = GlobalKey<FormState>();

  // Whether we have loaded the initial item data into the form.
  bool _initialized = false;

  // Original item snapshot used for dirty-checking.
  Item? _originalItem;

  // Form field values --------------------------------------------------
  late TextEditingController _nameController;
  late TextEditingController _modelController;
  late TextEditingController _serialController;
  late TextEditingController _storeController;
  late TextEditingController _priceController;
  late TextEditingController _warrantyProviderController;
  late TextEditingController _notesController;

  String _brand = '';
  ItemCategory _category = ItemCategory.other;
  ItemRoom? _room;
  DateTime _purchaseDate = DateTime.now();
  int _warrantyMonths = 12;
  WarrantyType _warrantyType = WarrantyType.manufacturer;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _modelController = TextEditingController();
    _serialController = TextEditingController();
    _storeController = TextEditingController();
    _priceController = TextEditingController();
    _warrantyProviderController = TextEditingController();
    _notesController = TextEditingController();
  }

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

  /// Populate form fields from loaded item (once).
  void _initializeFromItem(Item item) {
    if (_initialized) return;
    _initialized = true;
    _originalItem = item;

    _nameController.text = item.name;
    _brand = item.brand ?? '';
    _modelController.text = item.modelNumber ?? '';
    _serialController.text = item.serialNumber ?? '';
    _category = item.category;
    _room = item.room;
    _purchaseDate = item.purchaseDate;
    _storeController.text = item.store ?? '';
    _priceController.text =
        item.price != null ? item.price!.toStringAsFixed(2) : '';
    _warrantyMonths = item.warrantyMonths;
    _warrantyType = item.warrantyType;
    _warrantyProviderController.text = item.warrantyProvider ?? '';
    _notesController.text = item.notes ?? '';
  }

  /// Returns true if any form value differs from the original item.
  bool get _isDirty {
    final orig = _originalItem;
    if (orig == null) return false;

    return _nameController.text != orig.name ||
        _brand != (orig.brand ?? '') ||
        _modelController.text != (orig.modelNumber ?? '') ||
        _serialController.text != (orig.serialNumber ?? '') ||
        _category != orig.category ||
        _room != orig.room ||
        _purchaseDate != orig.purchaseDate ||
        _storeController.text != (orig.store ?? '') ||
        _priceController.text !=
            (orig.price != null ? orig.price!.toStringAsFixed(2) : '') ||
        _warrantyMonths != orig.warrantyMonths ||
        _warrantyType != orig.warrantyType ||
        _warrantyProviderController.text != (orig.warrantyProvider ?? '') ||
        _notesController.text != (orig.notes ?? '');
  }

  Future<void> _handleCancel() async {
    if (_isDirty) {
      final discard = await showHavenConfirmDialog(
        context,
        title: 'Discard changes?',
        body: 'You have unsaved changes that will be lost.',
        confirmLabel: 'Discard',
        isDestructive: true,
      );
      if (!discard || !mounted) return;
    }
    if (mounted) context.pop();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final orig = _originalItem;
    if (orig == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _saving = true);

    try {
      final updated = orig.copyWith(
        name: _nameController.text.trim(),
        brand: _brand.isNotEmpty ? _brand : null,
        clearBrand: _brand.isEmpty && orig.brand != null,
        modelNumber: _modelController.text.trim().isNotEmpty
            ? _modelController.text.trim()
            : null,
        clearModelNumber:
            _modelController.text.trim().isEmpty && orig.modelNumber != null,
        serialNumber: _serialController.text.trim().isNotEmpty
            ? _serialController.text.trim()
            : null,
        clearSerialNumber:
            _serialController.text.trim().isEmpty && orig.serialNumber != null,
        category: _category,
        room: _room,
        clearRoom: _room == null && orig.room != null,
        purchaseDate: _purchaseDate,
        store: _storeController.text.trim().isNotEmpty
            ? _storeController.text.trim()
            : null,
        clearStore:
            _storeController.text.trim().isEmpty && orig.store != null,
        price: _priceController.text.trim().isNotEmpty
            ? double.tryParse(_priceController.text.trim())
            : null,
        clearPrice:
            _priceController.text.trim().isEmpty && orig.price != null,
        warrantyMonths: _warrantyMonths,
        warrantyType: _warrantyType,
        warrantyProvider: _warrantyProviderController.text.trim().isNotEmpty
            ? _warrantyProviderController.text.trim()
            : null,
        clearWarrantyProvider:
            _warrantyProviderController.text.trim().isEmpty &&
                orig.warrantyProvider != null,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        clearNotes:
            _notesController.text.trim().isEmpty && orig.notes != null,
        updatedAt: DateTime.now(),
      );

      await ref.read(itemsProvider.notifier).updateItem(updated);
      ref.invalidate(itemDetailProvider(widget.itemId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item updated')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserMessage(e)),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Retry',
              textColor: HavenColors.primary,
              onPressed: _handleSave,
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPurchaseDate() async {
    HapticFeedback.lightImpact();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
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
      setState(() => _purchaseDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(itemDetailProvider(widget.itemId));
    final theme = Theme.of(context);

    return itemAsync.when(
      data: (item) {
        _initializeFromItem(item);

        final brandsAsync = ref.watch(brandSuggestionsProvider(_category));
        final brands = brandsAsync.valueOrNull ?? [];

        return PopScope(
          canPop: !_isDirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await _handleCancel();
          },
          child: Scaffold(
            backgroundColor: HavenColors.background,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: _handleCancel,
              ),
              title: const Text('Edit Item'),
              actions: [
                TextButton(
                  onPressed: _isDirty && !_saving ? _handleSave : null,
                  child: Text(
                    'Save Changes',
                    style: TextStyle(
                      color: _isDirty && !_saving
                          ? HavenColors.primary
                          : HavenColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            body: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(HavenSpacing.md),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name *
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Product Name *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Name is required' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Brand
                  BrandAutocompleteField(
                    brands: brands,
                    initialValue: _brand.isNotEmpty ? _brand : null,
                    onChanged: (value) {
                      setState(() => _brand = value);
                    },
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Model Number
                  TextFormField(
                    controller: _modelController,
                    decoration: const InputDecoration(labelText: 'Model Number'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Serial Number
                  TextFormField(
                    controller: _serialController,
                    decoration: const InputDecoration(labelText: 'Serial Number'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Category
                  DropdownButtonFormField<ItemCategory>(
                    value: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    dropdownColor: HavenColors.elevated,
                    items: ItemCategory.values
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.displayLabel),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _category = value);
                      }
                    },
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Room
                  RoomPicker(
                    value: _room,
                    onChanged: (value) {
                      setState(() => _room = value);
                    },
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Purchase Date *
                  InkWell(
                    onTap: _pickPurchaseDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Purchase Date *',
                        suffixIcon: Icon(
                          Icons.calendar_today,
                          size: 20,
                          color: HavenColors.textSecondary,
                        ),
                      ),
                      child: Text(
                        DateFormat.yMMMd().format(_purchaseDate),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Store
                  TextFormField(
                    controller: _storeController,
                    decoration: const InputDecoration(labelText: 'Store'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Price
                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefixText: '\$ ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Warranty Duration *
                  Text(
                    'Warranty Duration *',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: HavenColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  WarrantyDurationPicker(
                    initialMonths: _warrantyMonths,
                    onChanged: (months) {
                      setState(() => _warrantyMonths = months);
                    },
                    helperText: 'How long is the warranty coverage?',
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Warranty Type
                  DropdownButtonFormField<WarrantyType>(
                    value: _warrantyType,
                    decoration: const InputDecoration(labelText: 'Warranty Type'),
                    dropdownColor: HavenColors.elevated,
                    items: WarrantyType.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.displayLabel),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _warrantyType = value);
                      }
                    },
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Warranty Provider
                  TextFormField(
                    controller: _warrantyProviderController,
                    decoration:
                        const InputDecoration(labelText: 'Warranty Provider'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Notes
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                  ),

                  // Bottom spacing
                  const SizedBox(height: HavenSpacing.xxl),
                ],
              ),
            ),
          ),
        ),
        );
      },
      loading: () => Scaffold(
        backgroundColor: HavenColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => context.pop(),
          ),
          title: const Text('Edit Item'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            children: const [
              SkeletonLine(height: 48),
              SizedBox(height: HavenSpacing.md),
              SkeletonLine(height: 48),
              SizedBox(height: HavenSpacing.md),
              SkeletonLine(height: 48),
              SizedBox(height: HavenSpacing.md),
              SkeletonLine(height: 48),
              SizedBox(height: HavenSpacing.lg),
              SkeletonLine(height: 48),
            ],
          ),
        ),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: HavenColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => context.pop(),
          ),
          title: const Text('Edit Item'),
        ),
        body: ErrorStateWidget(
          message: ErrorHandler.getUserMessage(error),
          onRetry: () => ref.invalidate(itemDetailProvider(widget.itemId)),
        ),
      ),
    );
  }
}
