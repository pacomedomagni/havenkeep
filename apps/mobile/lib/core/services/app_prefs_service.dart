import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// User-controllable app preferences persisted to [SharedPreferences].
///
/// Holds the locale picker, theme picker, and "keep me signed in" toggle.
/// All three are surfaced in [SettingsScreen] (Ch05-F107..F121) and read
/// from `MaterialApp.router` so changes take effect without a restart.
class AppPrefsService {
  AppPrefsService._();

  static const _keyLocale = 'app_locale';
  static const _keyTheme = 'app_theme';
  static const _keyKeepSignedIn = 'app_keep_signed_in';

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// Read the persisted locale, or null if the user has never picked one
  /// (in which case we follow the system locale).
  static Future<Locale?> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLocale);
    if (raw == null || raw.isEmpty) return null;
    return Locale(raw);
  }

  static Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_keyLocale);
    } else {
      await prefs.setString(_keyLocale, locale.languageCode);
    }
  }

  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyTheme);
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        // Default to dark — matches HavenColors design language.
        return ThemeMode.dark;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, mode.name);
  }

  /// "Keep me signed in" — when false, sign-out fires on app cold-launch.
  /// Defaults to true; opt-out is the security-conscious choice.
  static Future<bool> getKeepSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKeepSignedIn) ?? true;
  }

  static Future<void> setKeepSignedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepSignedIn, value);
  }

  /// Open the platform-specific subscription management page (App Store on
  /// iOS, Google Play Store on Android). Used by the Premium screen so we
  /// route users to the OS-owned cancel flow instead of trying to handle
  /// subscription lifecycle ourselves.
  static Future<bool> openManageSubscription() async {
    Uri uri;
    if (Platform.isIOS) {
      uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    } else if (Platform.isAndroid) {
      uri = Uri.parse(
        'https://play.google.com/store/account/subscriptions',
      );
    } else {
      return false;
    }
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Notifier that persists locale changes and re-emits to listeners.
class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    state = await AppPrefsService.getLocale();
  }

  Future<void> set(Locale? locale) async {
    await AppPrefsService.setLocale(locale);
    state = locale;
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(),
);

/// Notifier that persists theme-mode changes.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    state = await AppPrefsService.getThemeMode();
  }

  Future<void> set(ThemeMode mode) async {
    await AppPrefsService.setThemeMode(mode);
    state = mode;
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

/// Notifier that persists the "keep me signed in" preference.
class KeepSignedInNotifier extends StateNotifier<bool> {
  KeepSignedInNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    state = await AppPrefsService.getKeepSignedIn();
  }

  Future<void> set(bool value) async {
    await AppPrefsService.setKeepSignedIn(value);
    state = value;
  }
}

final keepSignedInProvider =
    StateNotifierProvider<KeepSignedInNotifier, bool>(
  (ref) => KeepSignedInNotifier(),
);

/// Helper to check if [Platform] supports manage-subscription deep-linking
/// without dragging dart:io into widget files. Web/desktop returns false.
bool get manageSubscriptionSupported {
  if (kIsWeb) return false;
  return Platform.isIOS || Platform.isAndroid;
}
