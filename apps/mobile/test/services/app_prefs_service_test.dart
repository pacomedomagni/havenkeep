import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/services/app_prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppPrefsService.locale', () {
    test('returns null when no locale has been picked', () async {
      final locale = await AppPrefsService.getLocale();
      expect(locale, isNull);
    });

    test('round-trips a chosen locale through SharedPreferences', () async {
      await AppPrefsService.setLocale(const Locale('fr'));
      final locale = await AppPrefsService.getLocale();
      expect(locale?.languageCode, 'fr');
    });

    test('clears the locale when set(null) is called', () async {
      await AppPrefsService.setLocale(const Locale('fr'));
      await AppPrefsService.setLocale(null);
      final locale = await AppPrefsService.getLocale();
      expect(locale, isNull);
    });
  });

  group('AppPrefsService.themeMode', () {
    test('defaults to dark when no preference is stored', () async {
      final mode = await AppPrefsService.getThemeMode();
      expect(mode, ThemeMode.dark);
    });

    test('round-trips ThemeMode.light', () async {
      await AppPrefsService.setThemeMode(ThemeMode.light);
      expect(await AppPrefsService.getThemeMode(), ThemeMode.light);
    });

    test('round-trips ThemeMode.system', () async {
      await AppPrefsService.setThemeMode(ThemeMode.system);
      expect(await AppPrefsService.getThemeMode(), ThemeMode.system);
    });
  });

  group('AppPrefsService.keepSignedIn', () {
    test('defaults to true (secure cold-start state)', () async {
      expect(await AppPrefsService.getKeepSignedIn(), isTrue);
    });

    test('round-trips false', () async {
      await AppPrefsService.setKeepSignedIn(false);
      expect(await AppPrefsService.getKeepSignedIn(), isFalse);
    });
  });
}
