import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/providers/warranty_purchases_provider.dart';

/// Form to add a new warranty purchase.
class AddWarrantyPurchaseScreen extends ConsumerStatefulWidget {
  const AddWarrantyPurchaseScreen({super.key});

  @override
  ConsumerState<AddWarrantyPurchaseScreen> createState() =>
      _AddWarrantyPurchaseScreenState();
}

class _AddWarrantyPurchaseScreenState
    extends ConsumerState<AddWarrantyPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController();
  final _planController = TextEditingController();
  final _durationController = TextEditingController(text: '12');
  final _priceController = TextEditingController();
  final _deductibleController = TextEditingController(text: '0');
  final _claimLimitController = TextEditingController();
  final _policyController = TextEditingController();

  String? _selectedItemId;
  DateTime _startDate = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _providerController.dispose();
    _planController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _deductibleController.dispose();
    _claimLimitController.dispose();
    _policyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);
    final items = itemsAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Add Coverage')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          children: [
            _buildItemPicker(items),
            const SizedBox(height: HavenSpacing.md),
            _buildTextField(
              controller: _providerController,
              label: 'Provider',
              hint: 'e.g. SquareTrade',
            ),
            const SizedBox(height: HavenSpacing.sm),
            _buildTextField(
              controller: _planController,
              label: 'Plan Name',
              hint: 'e.g. 3-Year Protection',
            ),
            const SizedBox(height: HavenSpacing.sm),
            _buildTextField(
              controller: _policyController,
              label: 'Policy ID (optional)',
              requiredField: false,
            ),
            const SizedBox(height: HavenSpacing.md),
            _buildNumberField(
              controller: _durationController,
              label: 'Duration (months)',
            ),
            const SizedBox(height: HavenSpacing.sm),
            _buildDatePicker(context),
            const SizedBox(height: HavenSpacing.sm),
            _buildNumberField(
              controller: _priceController,
              label: 'Price',
              isCurrency: true,
            ),
            const SizedBox(height: HavenSpacing.sm),
            _buildNumberField(
              controller: _deductibleController,
              label: 'Deductible',
              isCurrency: true,
            ),
            const SizedBox(height: HavenSpacing.sm),
            _buildNumberField(
              controller: _claimLimitController,
              label: 'Claim Limit (optional)',
              isCurrency: true,
              requiredField: false,
            ),
            const SizedBox(height: HavenSpacing.lg),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting || items.isEmpty ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Warranty'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemPicker(List<Item> items) {
    return DropdownButtonFormField<String>(
      value: _selectedItemId,
      decoration: const InputDecoration(
        labelText: 'Item',
      ),
      items: items
          .map((item) => DropdownMenuItem<String>(
                value: item.id,
                child: Text(item.name),
              ))
          .toList(),
      onChanged: (value) => setState(() => _selectedItemId = value),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Select an item';
        }
        return null;
      },
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _startDate,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (picked != null) {
          setState(() => _startDate = picked);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Start Date'),
        child: Text(DateFormat.yMMMd().format(_startDate)),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool requiredField = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
      validator: (value) {
        if (requiredField && (value == null || value.trim().isEmpty)) {
          return 'Required';
        }
        return null;
      },
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    bool isCurrency = false,
    bool requiredField = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixText: isCurrency ? '\$' : null,
      ),
      validator: (value) {
        if (!requiredField) return null;
        if (value == null || value.trim().isEmpty) return 'Required';
        final parsed = double.tryParse(value);
        if (parsed == null) return 'Enter a number';
        return null;
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedItemId == null) return;

    setState(() => _submitting = true);

    try {
      final duration = int.tryParse(_durationController.text.trim()) ?? 12;
      final price = double.tryParse(_priceController.text.trim()) ?? 0;
      final deductible = double.tryParse(_deductibleController.text.trim()) ?? 0;
      final claimLimit = _claimLimitController.text.trim().isNotEmpty
          ? double.tryParse(_claimLimitController.text.trim())
          : null;

      final purchase = WarrantyPurchase(
        id: 'temp',
        itemId: _selectedItemId!,
        userId: '',
        provider: _providerController.text.trim(),
        planName: _planController.text.trim(),
        externalPolicyId: _policyController.text.trim().isNotEmpty
            ? _policyController.text.trim()
            : null,
        durationMonths: duration,
        startsAt: _startDate,
        expiresAt: _startDate,
        coverageDetails: null,
        price: price,
        deductible: deductible,
        claimLimit: claimLimit,
        commissionAmount: null,
        commissionRate: null,
        purchaseDate: DateTime.now(),
        stripePaymentIntentId: null,
        status: WarrantyPurchaseStatus.active,
        cancelledAt: null,
        cancellationReason: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ref.read(warrantyPurchasesProvider.notifier).addPurchase(purchase);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Warranty added')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
