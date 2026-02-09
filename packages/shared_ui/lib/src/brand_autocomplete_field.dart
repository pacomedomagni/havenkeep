import 'package:flutter/material.dart';
import 'theme.dart';

/// A brand name input field with autocomplete suggestions.
///
/// Shows a dropdown of matching brand names as the user types. An "Other..."
/// option is always appended. Selecting it replaces the autocomplete with a
/// plain text field for free-form entry.
class BrandAutocompleteField extends StatefulWidget {
  const BrandAutocompleteField({
    super.key,
    required this.brands,
    this.initialValue,
    required this.onChanged,
    this.validator,
    this.label = 'Brand',
  });

  /// Suggested brand names shown in the dropdown.
  final List<String> brands;

  /// Pre-filled value for the field.
  final String? initialValue;

  /// Called whenever the text value changes.
  final ValueChanged<String> onChanged;

  /// Optional form validator.
  final String? Function(String?)? validator;

  /// Label shown on the input decoration.
  final String label;

  @override
  State<BrandAutocompleteField> createState() =>
      _BrandAutocompleteFieldState();
}

class _BrandAutocompleteFieldState extends State<BrandAutocompleteField> {
  static const _otherOption = 'Other...';

  late bool _isOtherSelected;
  late TextEditingController _otherController;

  @override
  void initState() {
    super.initState();
    _isOtherSelected = widget.initialValue != null &&
        widget.initialValue!.isNotEmpty &&
        !widget.brands.contains(widget.initialValue);
    _otherController = TextEditingController(
      text: _isOtherSelected ? widget.initialValue : '',
    );
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  List<String> _filterOptions(TextEditingValue textEditingValue) {
    final query = textEditingValue.text.toLowerCase();
    final filtered = widget.brands
        .where((b) => b.toLowerCase().contains(query))
        .toList();
    filtered.add(_otherOption);
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (_isOtherSelected) {
      return TextFormField(
        controller: _otherController,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            icon: const Icon(
              Icons.close,
              size: HavenIconSize.compact,
              color: HavenColors.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _isOtherSelected = false;
                _otherController.clear();
              });
              widget.onChanged('');
            },
          ),
        ),
        validator: widget.validator,
        onChanged: widget.onChanged,
      );
    }

    return Autocomplete<String>(
      initialValue: widget.initialValue != null
          ? TextEditingValue(text: widget.initialValue!)
          : TextEditingValue.empty,
      optionsBuilder: _filterOptions,
      onSelected: (String selection) {
        if (selection == _otherOption) {
          setState(() {
            _isOtherSelected = true;
          });
          widget.onChanged('');
        } else {
          widget.onChanged(selection);
        }
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController controller,
        FocusNode focusNode,
        VoidCallback onFieldSubmitted,
      ) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: widget.label),
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<String> onSelected,
        Iterable<String> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            color: HavenColors.elevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HavenRadius.input),
              side: const BorderSide(color: HavenColors.border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final option = options.elementAt(index);
                  final isOther = option == _otherOption;
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: HavenSpacing.md,
                        vertical: HavenSpacing.sm + 2,
                      ),
                      child: Text(
                        option,
                        style: TextStyle(
                          color: isOther
                              ? HavenColors.secondary
                              : HavenColors.textPrimary,
                          fontStyle:
                              isOther ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
