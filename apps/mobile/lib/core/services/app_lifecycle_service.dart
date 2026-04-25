import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/items_provider.dart';
import '../providers/warranty_purchases_provider.dart';
import 'logging_service.dart';

/// Observes [AppLifecycleState] and refreshes warranty data when the user
/// brings HavenKeep back to the foreground.
///
/// Avoids the stale-state-after-cold-resume audit gap by refreshing both
/// the active items list and the extended-warranty coverage list on
/// `resumed`. Subscribes once in `main()` via [appLifecycleServiceProvider].
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService(this._ref);

  final Ref _ref;
  bool _registered = false;
  bool _disposed = false;

  /// Begin observing lifecycle events. Idempotent.
  void start() {
    if (_registered || _disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _registered = true;
  }

  void stop() {
    if (!_registered) return;
    WidgetsBinding.instance.removeObserver(this);
    _registered = false;
  }

  void disposeService() {
    stop();
    _disposed = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshOnResume();
  }

  void _refreshOnResume() {
    try {
      _ref.invalidate(itemsProvider);
      _ref.invalidate(warrantyPurchasesProvider);
    } catch (e, stack) {
      // Providers may not all be alive on cold-resume immediately after
      // sign-out; swallow the error so we never crash the lifecycle hook.
      LoggingService.warn(
        'Lifecycle resume refresh skipped',
        {'error': e.toString(), 'stack': stack.toString()},
      );
    }
  }

  /// iOS-only: returns true when the OS reports Background App Refresh is
  /// enabled. Schedulers should consult this before queueing local
  /// notifications so we don't spam users who've explicitly disabled
  /// background activity. On non-iOS platforms always returns true — the
  /// concept doesn't exist on Android.
  static Future<bool> backgroundRefreshAllowed() async {
    if (!Platform.isIOS) return true;
    // The platform doesn't expose a direct API from Dart, so we conservatively
    // allow scheduling and rely on the OS to enforce. The wrapper exists so
    // callers can be updated centrally if a Pigeon channel is added later.
    return true;
  }
}

final appLifecycleServiceProvider = Provider<AppLifecycleService>((ref) {
  final svc = AppLifecycleService(ref);
  ref.onDispose(svc.disposeService);
  return svc;
});
