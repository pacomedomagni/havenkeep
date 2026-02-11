import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'add_item_wizard_screen.dart';

/// Step 2: Warranty (purchase date, warranty length) - ~20 seconds.
class WizardStep2Warranty extends StatefulWidget {
  final WizardData data;
  final VoidCallback onNext;

  const WizardStep2Warranty({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<WizardStep2Warranty> createState() => _WizardStep2WarrantyState();
}

class _WizardStep2WarrantyState extends State<WizardStep2Warranty> {
  final List<int> _commonWarrantyLengths = [12, 24, 36, 60, 120];

  @override
  void initState() {
    super.initState();
    widget.data.purchaseDate ??= DateTime.now();
    widget.data.warrantyMonths ??= 12;
  }

  void _handleNext() {
    if (widget.data.purchaseDate != null && widget.data.warrantyMonths != null) {
      widget.onNext();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.data.purchaseDate ?? now,
      firstDate: DateTime(2000),
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
        widget.data.purchaseDate = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMMM d, y').format(date);
  }

  bool get _canContinue =>
      widget.data.purchaseDate != null && widget.data.warrantyMonths != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step title
          const Text(
            'When did you buy it?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: HavenColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Step 2 of 3',
            style: TextStyle(
              fontSize: 14,
              color: HavenColors.textSecondary,
            ),
          ),

          const SizedBox(height: 32),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Purchase date
                  const Text(
                    'Purchase Date',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HavenColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Semantics(
                    button: true,
                    label: 'Pick purchase date',
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: HavenColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: HavenColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                color: HavenColors.primary),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatDate(widget.data.purchaseDate!),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: HavenColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Tap to change',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: HavenColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: HavenColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Warranty length
                  const Text(
                    'Warranty Length',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HavenColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildWarrantyLengthOptions(),

                  const SizedBox(height: 16),

                  // Warranty end date preview
                  if (widget.data.purchaseDate != null &&
                      widget.data.warrantyMonths != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: HavenColors.active.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: HavenColors.active.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_outlined,
                              color: HavenColors.active),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Warranty expires:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDate(DateTime(widget.data.purchaseDate!.year, widget.data.purchaseDate!.month + widget.data.warrantyMonths!, widget.data.purchaseDate!.day)),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: HavenColors.active,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
    );
  }

  Widget _buildWarrantyLengthOptions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _commonWarrantyLengths.map((months) {
        final isSelected = widget.data.warrantyMonths == months;
        final years = months ~/ 12;
        final label = years > 0 ? '$years ${years == 1 ? 'Year' : 'Years'}' : '$months Months';

        return Semantics(
          selected: isSelected,
          label: label,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                widget.data.warrantyMonths = months;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isSelected ? HavenColors.primary : HavenColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? HavenColors.primary : HavenColors.border,
                  width: 2,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? HavenColors.textPrimary : HavenColors.textPrimary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
