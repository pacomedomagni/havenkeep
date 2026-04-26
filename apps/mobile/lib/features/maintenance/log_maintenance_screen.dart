import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/providers/maintenance_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/price_parser.dart';
import '../../core/widgets/haven_loader.dart';
import '../../core/utils/haven_haptics.dart';

/// Form to log a completed maintenance task.
///
/// Mountable two ways: as a full-screen route (default) or as a modal bottom
/// sheet via [showAsSheet]. The sheet path is what item_detail uses so the
/// user doesn't lose item context when they tap "Log maintenance".
class LogMaintenanceScreen extends ConsumerStatefulWidget {
  /// Pre-selected item id. When provided the item picker is hidden and the
  /// form skips straight to the task fields — matches the "log from this
  /// item's screen" entry path.
  final String? initialItemId;

  /// When true the form renders without a Scaffold/AppBar, so it can be
  /// mounted in a modal bottom sheet without doubling chrome.
  final bool embeddedInSheet;

  const LogMaintenanceScreen({
    super.key,
    this.initialItemId,
    this.embeddedInSheet = false,
  });

  /// Show the form in a modal bottom sheet pre-populated with [itemId].
  /// Returns once the sheet is dismissed.
  static Future<void> showAsSheet(
    BuildContext context, {
    required String itemId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HavenColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(HavenRadius.card)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => LogMaintenanceScreen(
            initialItemId: itemId,
            embeddedInSheet: true,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<LogMaintenanceScreen> createState() =>
      _LogMaintenanceScreenState();
}

class _LogMaintenanceScreenState extends ConsumerState<LogMaintenanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskNameController = TextEditingController();
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();
  final _costController = TextEditingController();

  DateTime _completedDate = DateTime.now();
  String? _selectedItemId;
  String? _selectedScheduleId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedItemId = widget.initialItemId;
  }

  @override
  void dispose() {
    _taskNameController.dispose();
    _notesController.dispose();
    _durationController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _completedDate,
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
    if (picked != null) setState(() => _completedDate = picked);
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an item')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Not signed in')),
          );
        }
        return;
      }

      // parsePriceInput tolerates "$1,299" / "1299.50" / locale formats —
      // double.tryParse silently coerced these to null (F064).
      final entry = MaintenanceHistory(
        id: '',
        userId: user.id,
        itemId: _selectedItemId!,
        scheduleId: _selectedScheduleId,
        taskName: _taskNameController.text.trim(),
        completedDate: _completedDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        durationMinutes: _durationController.text.trim().isEmpty
            ? null
            : int.tryParse(_durationController.text.trim()),
        cost: _costController.text.trim().isEmpty
            ? null
            : parsePriceInput(_costController.text.trim()),
        createdAt: DateTime.now(),
      );

      await ref.read(maintenanceRepositoryProvider).logTask(entry);

      if (mounted) {
        HavenHaptics.confirm();
        ref.invalidate(maintenanceDueProvider);
        ref.invalidate(maintenanceHistoryProvider);
        ref.invalidate(maintenanceHistoryByItemProvider(_selectedItemId!));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maintenance task logged')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);
    final dateFormat = DateFormat.yMMMd();
    // When the caller pinned a specific item, hide the picker and the
    // section label so the form goes straight to task fields.
    final showItemPicker = widget.initialItemId == null;

    final form = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(HavenSpacing.md),
        children: [
          if (widget.embeddedInSheet) ...[
            // Sheet handle so the sheet still feels draggable even though
            // the form scrolls.
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: HavenSpacing.md),
                decoration: BoxDecoration(
                  color: HavenColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Center(
              child: Text(
                'Log Maintenance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: HavenColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: HavenSpacing.lg),
          ],
          if (showItemPicker) ...[
            // Item picker
            const _SectionLabel('Item'),
            const SizedBox(height: HavenSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.md),
              decoration: BoxDecoration(
                color: HavenColors.surface,
                borderRadius: BorderRadius.circular(HavenRadius.card),
                border: Border.all(color: HavenColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedItemId,
                  isExpanded: true,
                  hint: const Text('Select an item',
                      style: TextStyle(color: HavenColors.textTertiary)),
                  dropdownColor: HavenColors.elevated,
                  style: const TextStyle(color: HavenColors.textPrimary),
                  items: itemsAsync.whenOrNull(
                    data: (items) => items.map((item) {
                      return DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.brand ?? ''} ${item.name}'.trim(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _selectedItemId = v;
                      _selectedScheduleId = null;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: HavenSpacing.lg),
          ], // showItemPicker

          // Schedule picker (visible only when an item is selected — either
          // pre-pinned by the caller or chosen via the picker above).
          if (_selectedItemId != null) ...[
            _buildSchedulePicker(itemsAsync),
            const SizedBox(height: HavenSpacing.lg),
          ],

          // Task name
          const _SectionLabel('Task Name'),
            const SizedBox(height: HavenSpacing.sm),
            TextFormField(
              controller: _taskNameController,
              style: const TextStyle(color: HavenColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g., Clean condenser coils',
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
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Task name required' : null,
            ),
            const SizedBox(height: HavenSpacing.lg),

            // Date
            const _SectionLabel('Date Completed'),
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
                      dateFormat.format(_completedDate),
                      style:
                          const TextStyle(color: HavenColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: HavenSpacing.lg),

            // Duration & Cost
            const _SectionLabel('Duration & Cost'),
            const SizedBox(height: HavenSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    style:
                        const TextStyle(color: HavenColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Minutes',
                      labelStyle: const TextStyle(
                          color: HavenColors.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: HavenColors.surface,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.card),
                        borderSide:
                            const BorderSide(color: HavenColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.card),
                        borderSide:
                            const BorderSide(color: HavenColors.border),
                      ),
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return null;
                      final v = int.tryParse(raw);
                      if (v == null || v < 0) return 'Enter a positive number';
                      if (v > 24 * 60) return 'Too long — under a day, please';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: HavenSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _costController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style:
                        const TextStyle(color: HavenColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Cost (\$)',
                      labelStyle: const TextStyle(
                          color: HavenColors.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: HavenColors.surface,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.card),
                        borderSide:
                            const BorderSide(color: HavenColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.card),
                        borderSide:
                            const BorderSide(color: HavenColors.border),
                      ),
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return null;
                      final v = parsePriceInput(raw);
                      if (v == null || v < 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: HavenSpacing.lg),

            // Notes
            const _SectionLabel('Notes'),
            const SizedBox(height: HavenSpacing.sm),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              style: const TextStyle(color: HavenColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Any additional notes...',
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
            ),
            const SizedBox(height: HavenSpacing.xl),

            // Submit
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: HavenLoader(),
                      )
                    : const Text('Log Task'),
              ),
            ),
          const SizedBox(height: HavenSpacing.xxl),
        ],
      ),
    );

    if (widget.embeddedInSheet) {
      return SafeArea(
        top: false,
        child: form,
      );
    }
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Log Maintenance')),
      body: form,
    );
  }

  /// Builds a schedule dropdown based on the selected item's category.
  Widget _buildSchedulePicker(AsyncValue<List<Item>> itemsAsync) {
    // Find the selected item to get its category
    final items = itemsAsync.valueOrNull ?? [];
    final selectedItem = items.where((i) => i.id == _selectedItemId).firstOrNull;

    if (selectedItem == null) return const SizedBox.shrink();

    final category = selectedItem.category.toJson(); // e.g. "refrigerator"
    final schedulesAsync = ref.watch(maintenanceSchedulesProvider(category));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Maintenance Schedule'),
        const SizedBox(height: HavenSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.md),
          decoration: BoxDecoration(
            color: HavenColors.surface,
            borderRadius: BorderRadius.circular(HavenRadius.card),
            border: Border.all(color: HavenColors.border),
          ),
          child: schedulesAsync.when(
            data: (schedules) {
              if (schedules.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: HavenSpacing.md),
                  child: Text(
                    'No schedules for this category',
                    style: TextStyle(
                      color: HavenColors.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                );
              }

              return DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedScheduleId,
                  isExpanded: true,
                  hint: const Text(
                    'Select a schedule (optional)',
                    style: TextStyle(color: HavenColors.textTertiary),
                  ),
                  dropdownColor: HavenColors.elevated,
                  style: const TextStyle(color: HavenColors.textPrimary),
                  items: [
                    // Allow clearing the selection
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'None (custom task)',
                        style: TextStyle(
                          color: HavenColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    ...schedules.map((schedule) {
                      final freq = schedule.frequencyMonths >= 12
                          ? 'Every ${schedule.frequencyMonths ~/ 12}y'
                          : 'Every ${schedule.frequencyMonths}mo';
                      return DropdownMenuItem(
                        value: schedule.id,
                        child: Text(
                          '${schedule.taskName} ($freq)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) {
                    setState(() {
                      final previousScheduleId = _selectedScheduleId;
                      _selectedScheduleId = v;
                      // Auto-fill task name when a schedule is selected:
                      // either the field is empty, or it currently matches
                      // the previous schedule's name (so the user hasn't
                      // overridden it). Prevents the picker becoming a
                      // no-op after the user clears the field (F065).
                      if (v != null) {
                        final schedule =
                            schedules.firstWhere((s) => s.id == v);
                        final current = _taskNameController.text.trim();
                        final previousName = previousScheduleId == null
                            ? null
                            : schedules
                                .where((s) => s.id == previousScheduleId)
                                .firstOrNull
                                ?.taskName;
                        if (current.isEmpty || current == previousName) {
                          _taskNameController.text = schedule.taskName;
                        }
                      }
                    });
                  },
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: SizedBox(
                width: 20,
                height: 20,
                child: HavenLoader(),
              ),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Text(
                'Could not load schedules',
                style: TextStyle(color: HavenColors.expired, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
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
