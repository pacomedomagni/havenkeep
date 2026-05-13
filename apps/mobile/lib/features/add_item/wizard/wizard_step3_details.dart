import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'add_item_wizard_screen.dart';
import '../../../core/utils/price_parser.dart';
import '../../../core/widgets/haven_loader.dart';

/// Step 3: Details (optional: price, store, room) - ~15 seconds.
class WizardStep3Details extends StatefulWidget {
  final WizardData data;
  final VoidCallback onSave;
  final bool isSaving;

  const WizardStep3Details({
    super.key,
    required this.data,
    required this.onSave,
    required this.isSaving,
  });

  @override
  State<WizardStep3Details> createState() => _WizardStep3DetailsState();
}

class _WizardStep3DetailsState extends State<WizardStep3Details> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _storeController = TextEditingController();
  final _notesController = TextEditingController();
  String? _priceError;

  @override
  void initState() {
    super.initState();
    _priceController.text = widget.data.price != null
        ? widget.data.price!.toStringAsFixed(2)
        : '';
    _storeController.text = widget.data.store ?? '';
    _notesController.text = widget.data.notes ?? '';
  }

  @override
  void dispose() {
    _priceController.dispose();
    _storeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleSave() {
    // Validate optional fields inline so users see the error next to the
    // field instead of a snackbar (Ch05 form-error inline requirement).
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final priceText = _priceController.text.trim();
    if (priceText.isEmpty) {
      widget.data.price = null;
    } else {
      // parsePriceInput tolerates locale-specific decimal separators and
      // strips currency cruft. The validator above already rejects bad input.
      widget.data.price = parsePriceInput(priceText);
    }

    widget.data.store = _storeController.text.trim().isNotEmpty
        ? _storeController.text.trim()
        : null;
    widget.data.notes = _notesController.text.trim().isNotEmpty
        ? _notesController.text.trim()
        : null;

    widget.onSave();
  }

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
            'Any other details?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: HavenColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Step 3 of 3 • All optional',
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
                  // Price (Ch05-F009: route through parsePriceInput; reject
                  // negatives + NaN + unreasonable values via inline error).
                  TextFormField(
                    controller: _priceController,
                    decoration: InputDecoration(
                      labelText: 'Purchase Price (Optional)',
                      hintText: 'e.g., 899.99',
                      prefixIcon: const Icon(Icons.attach_money),
                      errorText: _priceError,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      // Permit only digits + a single decimal separator (`.`
                      // or `,`); blocks negative signs and NaN-like input.
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]'),
                      ),
                      LengthLimitingTextInputFormatter(12),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = parsePriceInput(value);
                      if (parsed == null) return 'Enter a valid price';
                      if (parsed < 0) return 'Price cannot be negative';
                      if (parsed > 1000000) {
                        return 'Price seems too high';
                      }
                      return null;
                    },
                    onChanged: (_) {
                      if (_priceError != null) {
                        setState(() => _priceError = null);
                      }
                    },
                  ),

                  const SizedBox(height: 20),

                  // Store
                  TextFormField(
                    controller: _storeController,
                    decoration: const InputDecoration(
                      labelText: 'Store (Optional)',
                      hintText: 'e.g., Best Buy, Amazon',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                    maxLength: 100,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    buildCounter: _hideCounter,
                  ),

                  const SizedBox(height: 24),

                  // Room
                  const Text(
                    'Room (Optional)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HavenColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildRoomGrid(),

                  const SizedBox(height: 24),

                  // Notes (Ch05-F016: enforce a sane maxLength so a 10MB
                  // paste can't bloat sync payloads).
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      hintText: 'Any additional details...',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    maxLength: 2000,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    buildCounter: _hideCounter,
                  ),

                  const SizedBox(height: 16),

                  // Skip hint
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: HavenColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(HavenRadius.button),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: HavenColors.secondary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You can always add these details later from the item screen.',
                            style: TextStyle(
                              fontSize: 13,
                              color: HavenColors.secondary,
                            ),
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

          // Save button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: widget.isSaving ? null : _handleSave,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                ),
                backgroundColor: HavenColors.active,
              ),
              child: widget.isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: HavenLoader(color: Colors.white),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline),
                        SizedBox(width: 8),
                        Text(
                          'Save Item',
                          style: HavenText.titleLarge,
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 8),

          // Skip button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: widget.isSaving ? null : _handleSave,
              child: const Text('Skip & Save'),
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// Hide the default character counter that `maxLength` would otherwise
  /// display below the field; we still enforce the cap, just silently.
  Widget? _hideCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) =>
      null;

  Widget _buildRoomGrid() {
    final commonRooms = [
      ItemRoom.kitchen,
      ItemRoom.living_room,
      ItemRoom.bedroom,
      ItemRoom.office,
      ItemRoom.bathroom,
      ItemRoom.garage,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: commonRooms.map((room) {
        final isSelected = widget.data.room == room;
        return Semantics(
          selected: isSelected,
          label: room.displayLabel,
          child: InkWell(
            onTap: () {
              setState(() {
                widget.data.room = isSelected ? null : room;
              });
            },
            borderRadius: BorderRadius.circular(HavenRadius.button),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? HavenColors.primary : HavenColors.surface,
                borderRadius: BorderRadius.circular(HavenRadius.button),
                border: Border.all(
                  color: isSelected ? HavenColors.primary : HavenColors.border,
                ),
              ),
              child: Text(
                room.displayLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
