import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/services/notification_prefs_local.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/haven_loader.dart';

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

  // Local-only state (SharedPreferences)
  bool _digestEnabled = false;
  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 8, minute: 0);
  List<int> _reminderCascade = NotificationPrefsLocal.defaultReminderCascade;

  bool _isDirty = false;
  bool _isSaving = false;
  bool _isInitialized = false;

  static const _reminderDayOptions = [90, 60, 30, 14, 7];

  @override
  void initState() {
    super.initState();
    _loadLocalPrefs();
  }

  Future<void> _loadLocalPrefs() async {
    final digest = await NotificationPrefsLocal.isDigestEnabled();
    final quiet = await NotificationPrefsLocal.isQuietHoursEnabled();
    final startMin = await NotificationPrefsLocal.getQuietStartMinutes();
    final endMin = await NotificationPrefsLocal.getQuietEndMinutes();
    final cascade = await NotificationPrefsLocal.getReminderCascade();
    if (!mounted) return;
    setState(() {
      _digestEnabled = digest;
      _quietHoursEnabled = quiet;
      _quietStart = TimeOfDay(hour: startMin ~/ 60, minute: startMin % 60);
      _quietEnd = TimeOfDay(hour: endMin ~/ 60, minute: endMin % 60);
      _reminderCascade = cascade;
    });
  }

  Future<void> _toggleCascadeDay(int day) async {
    final next = List<int>.from(_reminderCascade);
    if (next.contains(day)) {
      next.remove(day);
    } else {
      next.add(day);
    }
    next.sort((a, b) => b.compareTo(a));
    setState(() => _reminderCascade = next);
    await NotificationPrefsLocal.setReminderCascade(next);
  }

  Future<void> _pickQuietTime({required bool isStart}) async {
    final initial = isStart ? _quietStart : _quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
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
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    if (isStart) {
      setState(() => _quietStart = picked);
      await NotificationPrefsLocal.setQuietStartMinutes(minutes);
    } else {
      setState(() => _quietEnd = picked);
      await NotificationPrefsLocal.setQuietEndMinutes(minutes);
    }
  }

  String _fmtTod(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final hour = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    return '$hour:${t.minute.toString().padLeft(2, '0')} $period';
  }

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

  // 4.14 / M-MED-06: when an external write (e.g. an admin tool, a
  // sync from another device, or a save-then-pop-and-return-to-screen
  // flow) replaces the server-side prefs, the screen should pick up
  // the new values — but ONLY if the user hasn't edited the form
  // since opening it. Stomping local edits with whatever the server
  // last said would surprise the user mid-form. The `_isDirty` guard
  // gives us a "live-update when idle, otherwise hold" semantic.
  void _onExternalPrefsUpdate(NotificationPreferences? prefs) {
    if (!_isInitialized) return;
    if (_isDirty) return;
    if (prefs == null) return;
    setState(() {
      _remindersEnabled = prefs.remindersEnabled;
      _firstReminderDays = prefs.firstReminderDays;
      _reminderTime = prefs.reminderTime;
      _warrantyOffersEnabled = prefs.warrantyOffersEnabled;
      _tipsEnabled = prefs.tipsEnabled;
      _pushEnabled = prefs.pushEnabled;
      _emailEnabled = prefs.emailEnabled;
    });
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      // The server generates the row's timestamps on upsert. The model
      // requires them after Phase 8 — supply local sentinels; the server
      // response (re-fetched via the invalidation below) overwrites them.
      final now = DateTime.now();
      final prefs = NotificationPreferences(
        userId: user.id,
        remindersEnabled: _remindersEnabled,
        firstReminderDays: _firstReminderDays,
        reminderTime: _reminderTime,
        warrantyOffersEnabled: _warrantyOffersEnabled,
        tipsEnabled: _tipsEnabled,
        pushEnabled: _pushEnabled,
        emailEnabled: _emailEnabled,
        createdAt: now,
        updatedAt: now,
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
          SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
        );
      }
    }
  }

  Future<void> _pickTime() async {
    final parts = _reminderTime.split(':');
    int hour = 9;
    int minute = 0;
    try {
      hour = int.parse(parts[0]);
      minute = int.parse(parts[1]);
    } catch (_) {
      // Fall back to 9:00 AM if parsing fails
    }
    final initialTime = TimeOfDay(hour: hour, minute: minute);

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
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } catch (_) {
      return time;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    // H82: don't mutate state inside build(). The previous
    // `prefsAsync.whenData(_initFromPrefs)` here wrote private fields
    // synchronously while building the tree — fragile under rebuild
    // edge cases. The listener below handles both initial population
    // (when _isInitialized is false → _initFromPrefs) and later
    // refreshes (when _isInitialized + !_isDirty → live-update).

    // 4.14 / M-MED-06: live-update when the upstream provider
    // emits new prefs and the user has nothing to lose. Guarded by
    // `_isDirty` inside `_onExternalPrefsUpdate`.
    ref.listen<AsyncValue<NotificationPreferences?>>(
      notificationPreferencesProvider,
      (previous, next) {
        next.whenData((prefs) {
          if (!_isInitialized) {
            _initFromPrefs(prefs);
          } else {
            _onExternalPrefsUpdate(prefs);
          }
        });
      },
    );

    // H82: prime the initial state if the provider's current value
    // is already available. ref.listen fires only on FUTURE changes;
    // when the user navigates here after the prefs were already
    // loaded by another screen, we'd otherwise stay in the loading
    // state forever. Read the synchronous valueOrNull and init.
    if (!_isInitialized) {
      prefsAsync.whenData((prefs) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isInitialized) _initFromPrefs(prefs);
        });
      });
    }

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Notification Preferences'),
      ),
      body: prefsAsync.when(
        data: (_) => _buildForm(),
        loading: () => const Padding(
          padding: EdgeInsets.all(HavenSpacing.md),
          child: Column(
            children: [
              SkeletonLine(height: 56),
              SizedBox(height: HavenSpacing.md),
              SkeletonLine(height: 56),
              SizedBox(height: HavenSpacing.md),
              SkeletonLine(height: 56),
              SizedBox(height: HavenSpacing.md),
              SkeletonLine(height: 56),
            ],
          ),
        ),
        error: (_, __) => Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(HavenSpacing.md, HavenSpacing.md, HavenSpacing.md, 0),
              padding: const EdgeInsets.all(HavenSpacing.md),
              decoration: BoxDecoration(
                color: HavenColors.expiring.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(HavenRadius.card),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: HavenColors.expiring, size: 20),
                  SizedBox(width: HavenSpacing.sm),
                  Expanded(
                    child: Text(
                      'Could not load your preferences. Showing defaults.',
                      style: TextStyle(color: HavenColors.expiring, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildForm()),
          ],
        ),
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

          const SizedBox(height: HavenSpacing.sm),

          // Reminder cascade (30/14/7 style). Persists locally.
          Container(
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.surface,
              borderRadius: BorderRadius.circular(HavenRadius.card),
              border: Border.all(color: HavenColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reminder schedule', style: HavenText.titleMedium),
                const SizedBox(height: 2),
                const Text(
                  'We\'ll ping you at each selected milestone.',
                  style: HavenText.caption,
                ),
                const SizedBox(height: HavenSpacing.sm),
                Wrap(
                  spacing: HavenSpacing.xs,
                  runSpacing: HavenSpacing.xs,
                  children: NotificationPrefsLocal.availableReminderDays
                      .map((day) {
                    final selected = _reminderCascade.contains(day);
                    return FilterChip(
                      label: Text('${day}d'),
                      selected: selected,
                      onSelected: (_) => _toggleCascadeDay(day),
                      checkmarkColor: HavenColors.textPrimary,
                      backgroundColor: HavenColors.elevated,
                      selectedColor: HavenColors.primary,
                      labelStyle: HavenText.caption.copyWith(
                        color: selected
                            ? HavenColors.textPrimary
                            : HavenColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(HavenRadius.chip),
                        side: BorderSide(
                          color: selected
                              ? HavenColors.primary
                              : HavenColors.border,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: HavenSpacing.lg),

        // ON-DEVICE section (digest + quiet hours)
        const SectionHeader(title: 'ON-DEVICE'),
        const SizedBox(height: HavenSpacing.sm),

        _buildSwitchTile(
          title: 'Daily Digest',
          subtitle: 'Group warranty reminders into one daily notification',
          value: _digestEnabled,
          onChanged: (v) async {
            setState(() => _digestEnabled = v);
            await NotificationPrefsLocal.setDigestEnabled(v);
          },
        ),
        const SizedBox(height: HavenSpacing.sm),
        _buildSwitchTile(
          title: 'Quiet Hours',
          subtitle: 'Silence notifications during your chosen window',
          value: _quietHoursEnabled,
          onChanged: (v) async {
            setState(() => _quietHoursEnabled = v);
            await NotificationPrefsLocal.setQuietHoursEnabled(v);
          },
        ),
        if (_quietHoursEnabled) ...[
          const SizedBox(height: HavenSpacing.sm),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickQuietTime(isStart: true),
                  child: Container(
                    padding: const EdgeInsets.all(HavenSpacing.md),
                    decoration: BoxDecoration(
                      color: HavenColors.surface,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                      border: Border.all(color: HavenColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Start',
                            style: TextStyle(
                                color: HavenColors.textTertiary,
                                fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(_fmtTod(_quietStart),
                            style: const TextStyle(
                                color: HavenColors.secondary,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: HavenSpacing.sm),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickQuietTime(isStart: false),
                  child: Container(
                    padding: const EdgeInsets.all(HavenSpacing.md),
                    decoration: BoxDecoration(
                      color: HavenColors.surface,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                      border: Border.all(color: HavenColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('End',
                            style: TextStyle(
                                color: HavenColors.textTertiary,
                                fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(_fmtTod(_quietEnd),
                            style: const TextStyle(
                                color: HavenColors.secondary,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
                    child: HavenLoader(color: Colors.white),
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
    return MergeSemantics(
      child: Container(
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
              activeTrackColor: HavenColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
