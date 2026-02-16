import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'add_item_wizard_screen.dart';

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
  final _priceController = TextEditingController();
  final _storeController = TextEditingController();
  final _notesController = TextEditingController();

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
    // Save optional fields
    widget.data.price = _priceController.text.isNotEmpty
        ? double.tryParse(_priceController.text)
        : null;
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
                  // Price
                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Purchase Price (Optional)',
                      hintText: 'e.g., 899.99',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
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

                  // Notes
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      hintText: 'Any additional details...',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                  ),

                  const SizedBox(height: 16),

                  // Skip hint
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: HavenColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor: HavenColors.active,
              ),
              child: widget.isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(HavenColors.textPrimary),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline),
                        SizedBox(width: 8),
                        Text(
                          'Save Item',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
    );
  }

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
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? HavenColors.primary : HavenColors.surface,
                borderRadius: BorderRadius.circular(12),
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
