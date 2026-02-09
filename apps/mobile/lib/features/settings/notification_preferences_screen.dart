import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/notifications_provider.dart';

/// Notification preferences screen.
///
/// Allows configuring warranty reminders, notification types, and delivery methods.
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  // Form state
  bool _remindersEnabled = true;
  int _firstReminderDays = 30;
  String _reminderTime = '09:00';
  bool _warrantyOffersEnabled = true;
  bool _tipsEnabled = true;
  bool _pushEnabled = true;
  bool _emailEnabled = false;

  bool _isDirty = false;
  bool _isSaving = false;
  bool _isInitialized = false;

  static const _reminderDayOptions = [90, 60, 30, 14, 7];

  void _initFromPrefs(NotificationPreferences? prefs) {
    if (_isInitialized) return;
    _isInitialized = true;

    if (prefs != null) {
      _remindersEnabled = prefs.remindersEnabled;
      _firstReminderDays = prefs.firstReminderDays;
      _reminderTime = prefs.reminderTime;
      _warrantyOffersEnabled = prefs.warrantyOffersEnabled;
      _tipsEnabled = prefs.tipsEnabled;
      _pushEnabled = prefs.pushEnabled;
      _emailEnabled = prefs.emailEnabled;
    }
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      final prefs = NotificationPreferences(
        userId: user.id,
        remindersEnabled: _remindersEnabled,
        firstReminderDays: _firstReminderDays,
        reminderTime: _reminderTime,
        warrantyOffersEnabled: _warrantyOffersEnabled,
        tipsEnabled: _tipsEnabled,
        pushEnabled: _pushEnabled,
        emailEnabled: _emailEnabled,
      );

      await ref
          .read(notificationsRepositoryProvider)
          .upsertPreferences(prefs);

      ref.invalidate(notificationPreferencesProvider);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isDirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _pickTime() async {
    final parts = _reminderTime.split(':');
    final initialTime = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: HavenColors.primary,
              surface: HavenColors.elevated,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _reminderTime =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
      _markDirty();
    }
  }

  String _formatTime(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    // Initialize form from loaded prefs
    prefsAsync.whenData((prefs) => _initFromPrefs(prefs));

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Notification Preferences'),
      ),
      body: prefsAsync.when(
        data: (_) => _buildForm(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildForm(), // Use defaults on error
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(HavenSpacing.md),
      children: [
        // WARRANTY REMINDERS section
        const SectionHeader(title: 'WARRANTY REMINDERS'),
        const SizedBox(height: HavenSpacing.sm),

        _buildSwitchTile(
          title: 'Warranty Reminders',
          subtitle: 'Get notified before warranties expire',
          value: _remindersEnabled,
          onChanged: (v) {
            setState(() => _remindersEnabled = v);
            _markDirty();
          },
        ),

        if (_remindersEnabled) ...[
          const SizedBox(height: HavenSpacing.sm),

          // First reminder days
          Container(
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.surface,
              borderRadius: BorderRadius.circular(HavenRadius.card),
              border: Border.all(color: HavenColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'First reminder',
                  style: TextStyle(
                    fontSize: 15,
                    color: HavenColors.textPrimary,
                  ),
                ),
                DropdownButton<int>(
                  value: _firstReminderDays,
                  dropdownColor: HavenColors.elevated,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(
                    fontSize: 15,
                    color: HavenColors.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                  items: _reminderDayOptions.map((days) {
                    return DropdownMenuItem(
                      value: days,
                      child: Text('$days days before'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _firstReminderDays = v);
                      _markDirty();
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: HavenSpacing.sm),

          // Reminder time
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.all(HavenSpacing.md),
              decoration: BoxDecoration(
                color: HavenColors.surface,
                borderRadius: BorderRadius.circular(HavenRadius.card),
                border: Border.all(color: HavenColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Reminder time',
                    style: TextStyle(
                      fontSize: 15,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  Text(
                    _formatTime(_reminderTime),
                    style: const TextStyle(
                      fontSize: 15,
                      color: HavenColors.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: HavenSpacing.lg),

        // OTHER NOTIFICATIONS section
        const SectionHeader(title: 'OTHER NOTIFICATIONS'),
        const SizedBox(height: HavenSpacing.sm),

        _buildSwitchTile(
          title: 'Warranty Offers',
          subtitle: 'Extended warranty and protection offers',
          value: _warrantyOffersEnabled,
          onChanged: (v) {
            setState(() => _warrantyOffersEnabled = v);
            _markDirty();
          },
        ),
        const SizedBox(height: HavenSpacing.sm),
        _buildSwitchTile(
          title: 'Tips & Suggestions',
          subtitle: 'Helpful tips for managing warranties',
          value: _tipsEnabled,
          onChanged: (v) {
            setState(() => _tipsEnabled = v);
            _markDirty();
          },
        ),

        const SizedBox(height: HavenSpacing.lg),

        // DELIVERY section
        const SectionHeader(title: 'DELIVERY'),
        const SizedBox(height: HavenSpacing.sm),

        _buildSwitchTile(
          title: 'Push Notifications',
          subtitle: 'Receive push notifications on this device',
          value: _pushEnabled,
          onChanged: (v) {
            setState(() => _pushEnabled = v);
            _markDirty();
          },
        ),
        const SizedBox(height: HavenSpacing.sm),
        _buildSwitchTile(
          title: 'Email Notifications',
          subtitle: 'Receive notifications via email',
          value: _emailEnabled,
          onChanged: (v) {
            setState(() => _emailEnabled = v);
            _markDirty();
          },
        ),

        const SizedBox(height: HavenSpacing.xl),

        // Save button
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isDirty && !_isSaving ? _save : null,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Changes'),
          ),
        ),

        const SizedBox(height: HavenSpacing.lg),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HavenSpacing.md,
        vertical: HavenSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    color: HavenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: HavenColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: HavenColors.primary,
          ),
        ],
      ),
    );
  }
}
