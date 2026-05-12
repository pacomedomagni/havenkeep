import 'dart:developer' as developer;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper for emitting Crashlytics breadcrumbs from anywhere in the
/// app without leaking the Firebase Crashlytics import into every service.
///
/// `dart:developer.log` is NOT automatically captured by Firebase
/// Crashlytics. Only `FirebaseCrashlytics.instance.log()` and `recordError`
/// flow into the next crash report's breadcrumb trail. Services that want
/// their operational events to be visible to on-call in production must
/// route through this helper instead of `debugPrint` or `developer.log`.
///
/// Safe to call before Firebase has initialised: the underlying SDK call
/// is wrapped in try/catch so a missing/uninitialised Firebase doesn't
/// crash callers. We also fall back to `developer.log` so the message
/// still appears in DevTools during local development.
class CrashlyticsBreadcrumb {
  /// Emit a breadcrumb visible in the next Crashlytics report. The
  /// `tag` is prepended to the message so multiple call sites are
  /// distinguishable in the breadcrumb trail (e.g. "[offline_sync] queue
  /// eviction").
  static void log(String tag, String message) {
    final line = '[$tag] $message';
    // Local developer log for DevTools / `flutter logs` parity.
    developer.log(line, name: tag);
    if (kIsWeb) return;
    try {
      FirebaseCrashlytics.instance.log(line);
    } catch (_) {
      // Firebase not ready / no API key in dev builds. The developer.log
      // call above is sufficient locally.
    }
  }
}
