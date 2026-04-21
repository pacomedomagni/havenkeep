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
import '../../core/widgets/haven_loader.dart';
import '../../core/utils/haven_haptics.dart';

/// Form to log a completed maintenance task.
class LogMaintenanceScreen extends ConsumerStatefulWidget {
  const LogMaintenanceScreen({super.key});

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
            : int.tryParse(_durationController.text),
        cost: _costController.text.trim().isEmpty
            ? null
            : double.tryParse(_costController.text),
        createdAt: DateTime.now(),
      );

      await ref.read(maintenanceRepositoryProvider).logTask(entry);

      if (mounted) {
        HavenHaptics.confirm();
        ref.invalidate(maintenanceDueProvider);
        ref.invalidate(maintenanceHistoryProvider);
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

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Log Maintenance')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          children: [
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

            // Schedule picker (visible only when an item is selected)
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
      ),
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
                      _selectedScheduleId = v;
                      // Auto-fill the task name when a schedule is selected
                      if (v != null) {
                        final schedule = schedules.firstWhere((s) => s.id == v);
                        if (_taskNameController.text.trim().isEmpty) {
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
