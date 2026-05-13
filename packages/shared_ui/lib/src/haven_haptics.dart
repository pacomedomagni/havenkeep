import 'package:flutter/services.dart';

/// Named haptic intents so every feature uses the same rule instead of
/// hand-rolling `HapticFeedback.lightImpact()` ad-hoc. This taxonomy is the
/// only sanctioned way to fire haptic feedback in HavenKeep.
///
/// Rules:
///   * [tap]       — most buttons, filter chips, list rows (light impact).
///                   The default — when in doubt, use this.
///   * [select]    — radio/toggle changes, picker confirmations,
///                   tab switches (selection click).
///   * [confirm]   — successful save / mark-done / primary action
///                   (medium impact). One per success.
///   * [celebrate] — celebration overlay, milestone moment, gift activation
///                   (heavy impact). Reserve for the wins.
///   * [warn]      — destructive confirmation, validation miss
///                   (heavy / vibrate). Reserve for "stop and think."
///
/// All calls are best-effort and silently no-op on platforms that don't
/// support haptics (web, some Linux flavors). Callers don't need to await.
class HavenHaptics {
  HavenHaptics._();

  static Future<void> tap() => HapticFeedback.lightImpact();
  static Future<void> select() => HapticFeedback.selectionClick();
  static Future<void> confirm() => HapticFeedback.mediumImpact();
  static Future<void> celebrate() => HapticFeedback.heavyImpact();
  static Future<void> warn() => HapticFeedback.vibrate();
}
