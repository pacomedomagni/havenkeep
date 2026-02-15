import 'package:flutter/material.dart';
import 'theme.dart';

/// Duration unit used by [WarrantyDurationPicker].
enum _DurationUnit { years, months }

/// A compound input for selecting a warranty duration as a number + unit pair.
///
/// The value is always reported to [onChanged] as total months. For example,
/// entering "2 Years" calls `onChanged(24)`.
class WarrantyDurationPicker extends StatefulWidget {
  const WarrantyDurationPicker({
    super.key,
    this.initialMonths = 12,
    required this.onChanged,
    this.helperText,
    this.validator,
  });

  /// Initial duration in months.
  final int initialMonths;

  /// Called whenever the duration changes, reporting total months.
  final ValueChanged<int> onChanged;

  /// Optional helper text displayed below the inputs.
  final String? helperText;

  /// Optional validator that receives the computed total months.
  final String? Function(int?)? validator;

  @override
  State<WarrantyDurationPicker> createState() => _WarrantyDurationPickerState();
}

class _WarrantyDurationPickerState extends State<WarrantyDurationPicker> {
  late _DurationUnit _unit;
  late TextEditingController _numberController;
  late int _number;

  @override
  void initState() {
    super.initState();
    if (widget.initialMonths >= 12 && widget.initialMonths % 12 == 0) {
      _unit = _DurationUnit.years;
      _number = widget.initialMonths ~/ 12;
    } else {
      _unit = _DurationUnit.months;
      _number = widget.initialMonths;
    }
    _numberController = TextEditingController(text: _number.toString());
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  int get _totalMonths =>
      _number * (_unit == _DurationUnit.years ? 12 : 1);

  void _onNumberChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed >= 1 && parsed <= 99) {
      setState(() {
        _number = parsed;
      });
      widget.onChanged(_totalMonths);
    }
    // If the input is invalid (null, < 1, or > 99), we keep the previous
    // valid _number value. The TextFormField validator will show an error
    // naturally via the validator callback below.
  }

  void _onUnitChanged(_DurationUnit? newUnit) {
    if (newUnit == null) return;
    setState(() {
      _unit = newUnit;
    });
    widget.onChanged(_totalMonths);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Number input
            SizedBox(
              width: 60,
              child: TextFormField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: HavenSpacing.sm,
                    vertical: HavenSpacing.sm + 4,
                  ),
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null || parsed < 1 || parsed > 99) {
                    return 'Enter a number from 1 to 99';
                  }
                  if (widget.validator != null) {
                    return widget.validator!(_totalMonths);
                  }
                  return null;
                },
                onChanged: _onNumberChanged,
              ),
            ),
            const SizedBox(width: HavenSpacing.sm),
            // Unit dropdown
            Expanded(
              child: DropdownButtonFormField<_DurationUnit>(
                value: _unit,
                decoration: const InputDecoration(
                  fillColor: HavenColors.surface,
                  filled: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: HavenSpacing.md,
                    vertical: HavenSpacing.sm + 4,
                  ),
                ),
                dropdownColor: HavenColors.elevated,
                items: const [
                  DropdownMenuItem(
                    value: _DurationUnit.years,
                    child: Text('Years'),
                  ),
                  DropdownMenuItem(
                    value: _DurationUnit.months,
                    child: Text('Months'),
                  ),
                ],
                onChanged: _onUnitChanged,
              ),
            ),
          ],
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: HavenSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: HavenSpacing.xs),
            child: Text(
              widget.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: HavenColors.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
