import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'theme.dart';

/// A dropdown picker for selecting an [ItemRoom].
///
/// Renders a [DropdownButtonFormField] with all room values. When
/// [includeNone] is true (the default), a "None" option with a `null` value
/// is shown at the top of the list.
class RoomPicker extends StatelessWidget {
  const RoomPicker({
    super.key,
    this.value,
    required this.onChanged,
    this.includeNone = true,
    this.label = 'Room',
  });

  /// The currently selected room, or `null` for no selection.
  final ItemRoom? value;

  /// Called when the user selects a room.
  final ValueChanged<ItemRoom?> onChanged;

  /// Whether to show a "None" option at the top of the list.
  final bool includeNone;

  /// Label shown on the input decoration.
  final String label;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ItemRoom?>(
      value: value,
      decoration: InputDecoration(labelText: label),
      dropdownColor: HavenColors.elevated,
      items: [
        if (includeNone)
          const DropdownMenuItem<ItemRoom?>(
            value: null,
            child: Text('None'),
          ),
        ...ItemRoom.values.map(
          (room) => DropdownMenuItem<ItemRoom?>(
            value: room,
            child: Text(room.displayLabel),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
