import 'package:flutter/services.dart';

/// Named haptic intents so every feature uses the same rule instead of
/// hand-rolling `HapticFeedback.lightImpact()` ad-hoc.
///
/// Rules:
///   * `tap`      — most buttons, filter chips, list rows (light)
///   * `select`   — radio/toggle changes, picker confirmations (selection)
///   * `confirm`  — successful save / mark-done / primary action (medium)
///   * `celebrate`— celebration overlay, milestone moment (heavy)
///   * `warn`     — destructive confirmation, validation miss (medium)
class HavenHaptics {
  HavenHaptics._();

  static Future<void> tap() => HapticFeedback.lightImpact();
  static Future<void> select() => HapticFeedback.selectionClick();
  static Future<void> confirm() => HapticFeedback.mediumImpact();
  static Future<void> celebrate() => HapticFeedback.heavyImpact();
  static Future<void> warn() => HapticFeedback.vibrate();
}
