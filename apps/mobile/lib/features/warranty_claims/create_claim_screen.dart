import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/providers/warranty_claims_provider.dart';

/// Screen to create a new warranty claim for a specific item.
class CreateClaimScreen extends ConsumerStatefulWidget {
  final String itemId;

  const CreateClaimScreen({super.key, required this.itemId});

  @override
  ConsumerState<CreateClaimScreen> createState() => _CreateClaimScreenState();
}

class _CreateClaimScreenState extends ConsumerState<CreateClaimScreen> {
  final _formKey = GlobalKey<FormState>();
  final _issueController = TextEditingController();
  final _repairController = TextEditingController();
  final _repairCostController = TextEditingController();
  final _amountSavedController = TextEditingController();
  final _outOfPocketController = TextEditingController();
  final _filedWithController = TextEditingController();
  final _claimNumberController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _claimDate = DateTime.now();
  ClaimStatus _status = ClaimStatus.pending;
  bool _saving = false;

  @override
  void dispose() {
    _issueController.dispose();
    _repairController.dispose();
    _repairCostController.dispose();
    _amountSavedController.dispose();
    _outOfPocketController.dispose();
    _filedWithController.dispose();
    _claimNumberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _claimDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: HavenColors.primary,
            surface: HavenColors.elevated,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _claimDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final claim = WarrantyClaim(
        id: '',
        userId: '',
        itemId: widget.itemId,
        claimDate: _claimDate,
        issueDescription: _issueController.text.trim().isEmpty
            ? null
            : _issueController.text.trim(),
        repairDescription: _repairController.text.trim().isEmpty
            ? null
            : _repairController.text.trim(),
        repairCost: double.tryParse(_repairCostController.text) ?? 0,
        amountSaved: double.tryParse(_amountSavedController.text) ?? 0,
        outOfPocket: _outOfPocketController.text.trim().isEmpty
            ? null
            : double.tryParse(_outOfPocketController.text),
        status: _status,
        filedWith: _filedWithController.text.trim().isEmpty
            ? null
            : _filedWithController.text.trim(),
        claimNumber: _claimNumberController.text.trim().isEmpty
            ? null
            : _claimNumberController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ref.read(claimsProvider.notifier).addClaim(claim);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Warranty claim created')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create claim: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(itemDetailProvider(widget.itemId));
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('New Warranty Claim')),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (item) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(HavenSpacing.md),
            children: [
              // Item info header
              Container(
                padding: const EdgeInsets.all(HavenSpacing.md),
                decoration: BoxDecoration(
                  color: HavenColors.elevated,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        color: HavenColors.primary, size: 24),
                    const SizedBox(width: HavenSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.brand ?? ''} ${item.name}'.trim(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: HavenColors.textPrimary,
                            ),
                          ),
                          Text(
                            item.warrantyType.displayLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: HavenColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Claim date
              _SectionLabel('Claim Date'),
              const SizedBox(height: HavenSpacing.sm),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(HavenSpacing.md),
                  decoration: BoxDecoration(
                    color: HavenColors.surface,
                    borderRadius: BorderRadius.circular(HavenRadius.card),
                    border: Border.all(color: HavenColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 18, color: HavenColors.textSecondary),
                      const SizedBox(width: HavenSpacing.sm),
                      Text(
                        dateFormat.format(_claimDate),
                        style: const TextStyle(color: HavenColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Status
              _SectionLabel('Status'),
              const SizedBox(height: HavenSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.md),
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                  border: Border.all(color: HavenColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ClaimStatus>(
                    value: _status,
                    isExpanded: true,
                    dropdownColor: HavenColors.elevated,
                    style: const TextStyle(color: HavenColors.textPrimary),
                    items: ClaimStatus.values.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s.displayLabel),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _status = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Issue description
              _SectionLabel('Issue Description'),
              const SizedBox(height: HavenSpacing.sm),
              _buildTextField(
                controller: _issueController,
                hint: 'What went wrong?',
                maxLines: 3,
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Repair description
              _SectionLabel('Repair Description'),
              const SizedBox(height: HavenSpacing.sm),
              _buildTextField(
                controller: _repairController,
                hint: 'What was done to fix it?',
                maxLines: 3,
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Costs
              _SectionLabel('Costs'),
              const SizedBox(height: HavenSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _buildCurrencyField(
                      controller: _repairCostController,
                      label: 'Repair Cost',
                      required: true,
                    ),
                  ),
                  const SizedBox(width: HavenSpacing.sm),
                  Expanded(
                    child: _buildCurrencyField(
                      controller: _amountSavedController,
                      label: 'Amount Saved',
                      required: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HavenSpacing.sm),
              _buildCurrencyField(
                controller: _outOfPocketController,
                label: 'Out of Pocket (optional)',
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Filed with & claim number
              _SectionLabel('Claim Details'),
              const SizedBox(height: HavenSpacing.sm),
              _buildTextField(
                controller: _filedWithController,
                hint: 'Filed with (e.g. LG, Home Depot)',
              ),
              const SizedBox(height: HavenSpacing.sm),
              _buildTextField(
                controller: _claimNumberController,
                hint: 'Claim number (optional)',
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Notes
              _SectionLabel('Notes'),
              const SizedBox(height: HavenSpacing.sm),
              _buildTextField(
                controller: _notesController,
                hint: 'Any additional notes...',
                maxLines: 3,
              ),
              const SizedBox(height: HavenSpacing.xl),

              // Submit button
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Claim'),
                ),
              ),
              const SizedBox(height: HavenSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: HavenColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: HavenColors.textTertiary),
        filled: true,
        fillColor: HavenColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
          borderSide: const BorderSide(color: HavenColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
          borderSide: const BorderSide(color: HavenColors.border),
        ),
      ),
    );
  }

  Widget _buildCurrencyField({
    required TextEditingController controller,
    required String label,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: HavenColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: HavenColors.textSecondary, fontSize: 13),
        prefixText: '\$ ',
        prefixStyle: const TextStyle(color: HavenColors.textPrimary),
        filled: true,
        fillColor: HavenColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
          borderSide: const BorderSide(color: HavenColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
          borderSide: const BorderSide(color: HavenColors.border),
        ),
      ),
      validator: required
          ? (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (double.tryParse(v) == null) return 'Invalid number';
              return null;
            }
          : null,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: HavenColors.textTertiary,
        letterSpacing: 1.2,
      ),
    );
  }
}
