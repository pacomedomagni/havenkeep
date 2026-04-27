import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../router/router.dart';
import 'logging_service.dart';

/// Listens for inbound deep links and routes them through the app router.
///
/// Supported schemes:
/// - `havenkeep://gift/<code>` (custom URL scheme — iOS + Android)
/// - `havenkeep://referral/<code>` (already wired through the router)
/// - `https://havenkeep.com/gift/<code>` (Universal Link / App Link)
///
/// The native side is configured in:
/// - `apps/mobile/ios/Runner/Info.plist` — `CFBundleURLTypes` + Associated
///   Domains entitlement.
/// - `apps/mobile/android/app/src/main/AndroidManifest.xml` — intent-filter
///   on the launch activity.
class DeepLinkService {
  DeepLinkService(this._ref);

  final Ref _ref;
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _sub;

  /// Start listening for deep links. Idempotent — calling twice is a no-op.
  Future<void> initialize() async {
    if (_appLinks != null) return;
    _appLinks = AppLinks();

    // Cold-start link (app was launched from a tap on a gift URL).
    try {
      final initial = await _appLinks!.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
    } catch (e, stack) {
      LoggingService.error('Deep link cold-start handle failed', e, stack);
    }

    // Warm links (app already running).
    _sub = _appLinks!.uriLinkStream.listen(
      _handle,
      onError: (Object e, StackTrace s) {
        LoggingService.error('Deep link stream error', e, s);
      },
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _appLinks = null;
  }

  /// Map [uri] to an in-app route and push it. Unknown links are dropped.
  void _handle(Uri uri) {
    final route = routeFor(uri);
    if (route == null) {
      if (kDebugMode) {
        debugPrint('[DeepLinks] Ignoring unrecognized URI: $uri');
      }
      return;
    }
    try {
      final router = _ref.read(routerProvider);
      router.push(route);
    } catch (e) {
      LoggingService.error(
          'Deep link navigation failed', e, StackTrace.current);
    }
  }

  /// Convert an inbound [uri] to an in-app route, or `null` when the URI
  /// doesn't match any of the deep link contracts. Pure function so it can
  /// be unit-tested without a router.
  static String? routeFor(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    bool hasHost(String host) {
      // Custom scheme `havenkeep://gift/<code>` puts the verb in the host.
      return uri.host == host;
    }

    bool firstSegmentIs(String value) {
      return segments.isNotEmpty && segments.first == value;
    }

    // S3-K: every code we accept from a deep link must match this regex.
    // Server-issued gift / referral codes are alphanumeric with optional
    // dashes/underscores; anything else is a path traversal attempt or a
    // crafted URL trying to smuggle a route segment through.
    bool isValidCode(String code) =>
        code.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(code);

    // havenkeep://gift/<code> — partner activation code, distinct from
    // referral codes. Routes to the gift activation flow with the code
    // pre-filled.
    if (uri.scheme == 'havenkeep' && hasHost('gift') && segments.isNotEmpty) {
      final code = segments.first.trim();
      if (!isValidCode(code)) return null;
      return '/gift/$code';
    }

    // havenkeep://referral/<code>
    if (uri.scheme == 'havenkeep' &&
        hasHost('referral') &&
        segments.isNotEmpty) {
      final code = segments.first.trim();
      if (!isValidCode(code)) return null;
      return '/referral/$code';
    }

    // Universal Links: https://havenkeep.com/gift/<code>
    if (uri.host == 'havenkeep.com' &&
        firstSegmentIs('gift') &&
        segments.length >= 2) {
      final code = segments[1].trim();
      if (!isValidCode(code)) return null;
      return '/gift/$code';
    }

    // Universal Links: https://havenkeep.com/referral/<code>
    if (uri.host == 'havenkeep.com' &&
        firstSegmentIs('referral') &&
        segments.length >= 2) {
      final code = segments[1].trim();
      if (!isValidCode(code)) return null;
      return '/referral/$code';
    }

    return null;
  }

  /// Build the share URL for a given gift activation [code]. Used by the
  /// gifts UI when the user taps "Share" — we share the Universal Link so
  /// recipients can either open the app directly (when installed) or fall
  /// through to the marketing site (when not).
  static Uri shareUrlForGift(String code) {
    return Uri.parse('https://havenkeep.com/gift/$code');
  }

  /// Open the platform share sheet with a gift activation URL.
  static Future<void> shareGiftLink(String code, {String? subject}) async {
    final url = shareUrlForGift(code).toString();
    await SharePlus.instance.share(
      ShareParams(
        text: 'Activate your HavenKeep gift here: $url',
        subject: subject,
      ),
    );
  }
}

/// Riverpod provider — initialized at app start, disposed on tear-down.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final svc = DeepLinkService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});
