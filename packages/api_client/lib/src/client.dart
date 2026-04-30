import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// 3.8: per-request id used to correlate a mobile call with the server log
/// line. The server's request-logger accepts incoming `x-request-id`
/// values matching `^[A-Za-z0-9._-]{1,64}$`, so we generate 32 hex
/// characters (128 bits) which fits comfortably. Random.secure is
/// sufficient for correlation; this is not a security identifier.
final _Random_requestIds = Random.secure();
String _generateRequestId() {
  final bytes = List<int>.generate(16, (_) => _Random_requestIds.nextInt(256));
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Base type for every error the API client surfaces.
///
/// Sealed so callers can [`switch`] over the closed set of subclasses and
/// know they have handled every transport-level failure mode the client
/// can produce. The constructor order is `(statusCode, message)` with
/// optional named fields so we avoid breaking the existing throw sites
/// scattered across the mobile app.
sealed class ApiException implements Exception {
  const ApiException(
    this.statusCode,
    this.message, {
    this.code,
    this.retryAfterSeconds,
  });

  /// HTTP status code (or 0 for transport-level failures).
  final int statusCode;

  /// Human-readable error message safe to surface in logs (already
  /// scrubbed of bearer tokens / JWTs by [redactSensitive]).
  final String message;

  /// Machine-readable error code from the API's typed error envelope
  /// (`{ "code": "validation_error", ... }`). Null when not provided.
  final String? code;

  /// `Retry-After` header value (seconds) on 429 responses; null otherwise.
  final int? retryAfterSeconds;

  // -- legacy convenience flags. New code should `switch` on the subtype.
  bool get isUnauthorized => this is ApiAuthRequiredException;
  bool get isForbidden => this is ApiForbiddenException;
  bool get isNotFound => this is ApiNotFoundException;
  bool get isConflict => this is ApiConflictException;
  bool get isRateLimited => this is ApiRateLimitedException;
  bool get isServerError => this is ApiServerException;

  /// Mint the right subclass for a given HTTP status. Used by the client
  /// after parsing the response envelope; tests can call it too.
  factory ApiException.fromResponse(
    int statusCode,
    String message, {
    String? code,
    int? retryAfterSeconds,
  }) {
    if (statusCode == 401) {
      return ApiAuthRequiredException(statusCode, message, code: code);
    }
    if (statusCode == 403) {
      return ApiForbiddenException(statusCode, message, code: code);
    }
    if (statusCode == 404) {
      return ApiNotFoundException(statusCode, message, code: code);
    }
    if (statusCode == 409) {
      return ApiConflictException(statusCode, message, code: code);
    }
    if (statusCode == 422 || statusCode == 400) {
      return ApiValidationException(statusCode, message, code: code);
    }
    if (statusCode == 429) {
      return ApiRateLimitedException(
        statusCode,
        message,
        code: code,
        retryAfterSeconds: retryAfterSeconds,
      );
    }
    if (statusCode >= 500) {
      return ApiServerException(statusCode, message, code: code);
    }
    return ApiUnknownException(statusCode, message, code: code);
  }

  @override
  String toString() => '$runtimeType($statusCode): $message';
}

/// 401 — credentials missing or expired. The mobile app uses this to
/// trigger token refresh / sign-out flows.
final class ApiAuthRequiredException extends ApiException {
  const ApiAuthRequiredException(super.statusCode, super.message, {super.code});
}

/// 403 — authenticated but not allowed. Common for premium-only
/// features hit by free-plan users.
final class ApiForbiddenException extends ApiException {
  const ApiForbiddenException(super.statusCode, super.message, {super.code});
}

/// 404 — resource not found.
final class ApiNotFoundException extends ApiException {
  const ApiNotFoundException(super.statusCode, super.message, {super.code});
}

/// 400 / 422 — request body failed server-side validation.
final class ApiValidationException extends ApiException {
  const ApiValidationException(super.statusCode, super.message, {super.code});
}

/// 429 — rate limited. [retryAfterSeconds] is populated when the server
/// included a `Retry-After` header.
final class ApiRateLimitedException extends ApiException {
  const ApiRateLimitedException(
    super.statusCode,
    super.message, {
    super.code,
    super.retryAfterSeconds,
  });
}

/// 409 — server-side state conflicts with the request (used by the
/// offline sync queue's last-write-wins guard rails).
final class ApiConflictException extends ApiException {
  const ApiConflictException(super.statusCode, super.message, {super.code});
}

/// 5xx — server crashed / dependency failed. Always retriable.
final class ApiServerException extends ApiException {
  const ApiServerException(super.statusCode, super.message, {super.code});
}

/// Connectivity / DNS / TCP failures. `statusCode` is always 0 — there
/// was no HTTP response to extract one from.
final class ApiNetworkException extends ApiException {
  const ApiNetworkException(String message, {String? code})
      : super(0, message, code: code);
}

/// Request timed out before any bytes came back.
final class ApiTimeoutException extends ApiException {
  const ApiTimeoutException(String message, {String? code})
      : super(0, message, code: code);
}

/// Catch-all for any HTTP status the typed map doesn't recognise. Lets
/// callers still pattern-match the sealed hierarchy without losing
/// fidelity for, e.g., 451 / 418 responses.
final class ApiUnknownException extends ApiException {
  const ApiUnknownException(super.statusCode, super.message, {super.code});
}

/// Auth state for the local auth stream.
enum ApiAuthState {
  signedIn,
  signedOut,
  tokenRefreshed,
}

/// Mask `Bearer <token>` and JWT-shaped tokens in any string before it is
/// handed to the log callback or surfaced through an [ApiException]. The
/// callback is provided by the host app and may forward the message to a
/// remote sink (Loki, custom collector), so leaking access tokens in those
/// breadcrumbs would let an attacker who reads the log replay full sessions.
///
/// Top-level so callers (and tests) can reuse the exact regex set the client
/// uses internally.
String redactSensitive(String input) {
  // `Bearer <opaque>` — strip the token after the keyword.
  var out = input.replaceAll(
    RegExp(r'Bearer\s+[^\s"]+', caseSensitive: false),
    'Bearer [REDACTED]',
  );
  // Standalone JWTs (header.payload.signature, base64url alphabet).
  out = out.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    '[REDACTED_JWT]',
  );
  return out;
}

/// HTTP API client for the HavenKeep Express backend.
///
/// Manages JWT tokens (access + refresh) in secure storage,
/// auto-refreshes expired access tokens, and provides typed
/// convenience methods for REST operations.
///
/// ## TLS pinning (release builds)
///
/// The constructor accepts an injected [http.Client] so release builds can
/// pass an [IOClient] backed by a [SecurityContext] pinned to the issuer's
/// SPKI. The default client uses the platform trust store, which is fine
/// for development but lets a device with a custom CA installed MITM the
/// API. Mobile bootstrap should construct the pinned client and pass it in:
///
/// ```dart
/// final pinned = IOClient(
///   HttpClient(context: SecurityContext(withTrustedRoots: false))
///     ..badCertificateCallback = (cert, host, port) =>
///         _spkiMatches(cert, expectedSpkiSha256),
/// );
/// final client = ApiClient(baseUrl: env.apiBaseUrl, httpClient: pinned);
/// ```
///
/// ## URL safety
///
/// Always prefer the segments-based methods (e.g. `get(pathSegments: ['items',
/// itemId])`) over the legacy `path:` API. Segments are percent-encoded by
/// `Uri`, so even if a caller passes user-controlled input as a path segment
/// the request can't be tricked into hitting a different endpoint via path
/// traversal or unencoded slashes. The `path:` API remains for the few
/// hard-coded routes that contain no interpolated values.
///
/// ## Idempotency
///
/// All mutating methods (`post`/`put`/`patch`/`delete`/`upload`) accept an
/// optional `idempotencyKey`. When supplied it is forwarded as the
/// `Idempotency-Key` header — the API uses it to dedupe at-least-once
/// retries from the offline sync queue (Phase 6) so a flaky connection
/// can't accidentally book the same gift twice.
class ApiClient {
  final String baseUrl;
  final http.Client _http;
  final FlutterSecureStorage _storage;
  final void Function(String)? _onLog;

  String? _accessToken;
  String? _userId;
  Completer<void>? _refreshCompleter;

  final StreamController<ApiAuthState> _authStateController =
      StreamController<ApiAuthState>.broadcast();

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserId = 'user_id';

  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    FlutterSecureStorage? storage,
    void Function(String)? onLog,
  })  : _http = httpClient ?? http.Client(),
        _onLog = onLog,
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              // S-H8 (audit): device-bound keychain access. The prior
              // first_unlock class roams via iCloud Keychain — an
              // attacker who compromises the user's Apple ID + iCloud
              // Keychain on a fresh device can restore the HavenKeep
              // access/refresh tokens and hit the API as the user
              // without ever knowing the password.
              //
              // first_unlock_this_device is NOT iCloud-replicable
              // (matches the SQLCipher DB key in
              // secure_storage_service.dart S-HI-06). Trade-off: the
              // user pays a one-time "sign in again on a new device"
              // cost; that's the right trust delta for an auth token.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  /// Log a message via the callback and, in debug mode, via debugPrint.
  ///
  /// All messages are passed through [redactSensitive] first so a Bearer
  /// header or JWT that ended up in an error string never reaches the sink.
  void _log(String message) {
    final safe = redactSensitive(message);
    if (kDebugMode) {
      debugPrint(safe);
    }
    _onLog?.call(safe);
  }

  /// Stream of auth state changes (signedIn, signedOut, tokenRefreshed).
  Stream<ApiAuthState> get authStateChanges => _authStateController.stream;

  /// The current user's ID (decoded from stored data).
  String? get currentUserId => _userId;

  /// Whether the user has a valid token stored.
  bool get isAuthenticated => _accessToken != null;

  // ============================================
  // INITIALIZATION
  // ============================================

  /// Load stored tokens on app startup.
  /// Returns true if a valid session was restored.
  ///
  /// H-B9 (audit): the prior expired-token-on-restore branch cleared
  /// tokens on ANY refresh failure (network blip, 502, timeout). A
  /// user launching the app in a tunnel or while api.havenkeep.io
  /// was having a 30-second incident got thrown back to the welcome
  /// screen. Now: only ApiAuthRequiredException (the refresh token
  /// itself was rejected — i.e. the credential is genuinely dead)
  /// clears tokens. Transport errors (ApiNetworkException,
  /// ApiTimeoutException, ApiServerException) leave the tokens in
  /// place and surface as a "we're offline" state — the next launch
  /// can retry the refresh against fresher infra.
  Future<bool> restoreSession() async {
    try {
      _accessToken = await _storage.read(key: _keyAccessToken);
      final refreshToken = await _storage.read(key: _keyRefreshToken);
      _userId = await _storage.read(key: _keyUserId);

      if (_accessToken != null && refreshToken != null && _userId != null) {
        // Validate JWT expiration before accepting the restored token
        if (_isTokenExpired(_accessToken!)) {
          _log('[ApiClient] Stored access token is expired, refreshing...');
          try {
            await refreshAccessToken()
                .timeout(const Duration(seconds: 10));
            return true;
          } on ApiAuthRequiredException catch (e) {
            // Refresh token genuinely rejected — credentials dead.
            _log('[ApiClient] Refresh token rejected during restore: $e');
            await clearTokens();
            return false;
          } catch (e) {
            // Network / timeout / 5xx — keep tokens, return false so
            // the caller surfaces an offline state. The next app
            // launch will retry against the same stored credentials.
            _log('[ApiClient] Refresh transient failure during restore (keeping tokens): $e');
            return false;
          }
        }
        _authStateController.add(ApiAuthState.signedIn);
        return true;
      }

      // If we have a refresh token but no access token, try refreshing
      if (refreshToken != null && _userId != null) {
        try {
          await refreshAccessToken()
              .timeout(const Duration(seconds: 10));
          return true;
        } on ApiAuthRequiredException catch (e) {
          _log('[ApiClient] Refresh token rejected during restore: $e');
          await clearTokens();
          return false;
        } catch (e) {
          _log('[ApiClient] Refresh transient failure during restore (keeping tokens): $e');
          return false;
        }
      }

      return false;
    } catch (e) {
      _log('[ApiClient] Failed to restore session: $e');
      return false;
    }
  }

  /// Decode a JWT and check if the `exp` claim indicates the token is expired.
  /// Note: This does NOT verify the JWT signature — it only reads the expiry
  /// claim for local scheduling. The server validates signatures on every request.
  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // Decode the payload (second segment)
      String payload = parts[1];
      // Pad to multiple of 4 for base64 decoding
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }

      final decoded = utf8.decode(base64Url.decode(payload));
      final claims = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = claims['exp'] as int?;

      if (exp == null) return true;

      final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      // Consider expired if less than 30 seconds remaining
      return DateTime.now().isAfter(
        expirationDate.subtract(const Duration(seconds: 30)),
      );
    } catch (e) {
      _log('[ApiClient] Failed to decode JWT for expiration check: $e');
      return true;
    }
  }

  // ============================================
  // TOKEN MANAGEMENT
  // ============================================

  /// Store tokens after login/register.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    _accessToken = accessToken;
    _userId = userId;
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyUserId, value: userId);
    _authStateController.add(ApiAuthState.signedIn);
  }

  /// Clear all tokens (on logout).
  Future<void> clearTokens() async {
    _accessToken = null;
    _userId = null;
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUserId);
    _authStateController.add(ApiAuthState.signedOut);
  }

  /// Refresh the access token using the stored refresh token.
  /// Uses a mutex to prevent concurrent refresh requests.
  Future<void> refreshAccessToken() async {
    // If a refresh is already in progress, wait for it
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<void>();
    try {
      final refreshToken = await _storage.read(key: _keyRefreshToken);
      if (refreshToken == null) {
        throw const ApiAuthRequiredException(401, 'No refresh token available');
      }

      final response = await _http.post(
        _buildUri(pathSegments: const ['api', 'v1', 'auth', 'refresh']),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        // Standard envelope `{ success, data: { accessToken, refreshToken } }`
        // with legacy flat fallback.
        final data = body['data'] is Map<String, dynamic>
            ? body['data'] as Map<String, dynamic>
            : body;
        final accessToken = data['accessToken'] as String?;
        if (accessToken == null) {
          throw const ApiAuthRequiredException(
            401,
            'Token refresh response missing accessToken',
          );
        }
        _accessToken = accessToken;
        await _storage.write(key: _keyAccessToken, value: _accessToken!);
        final newRefreshToken = data['refreshToken'] as String?;
        if (newRefreshToken != null) {
          await _storage.write(key: _keyRefreshToken, value: newRefreshToken);
        }
        _authStateController.add(ApiAuthState.tokenRefreshed);
        _refreshCompleter!.complete();
      } else {
        // Refresh failed — force sign out
        await clearTokens();
        const error = ApiAuthRequiredException(
          401,
          'Session expired. Please sign in again.',
        );
        _refreshCompleter!.completeError(error);
        throw error;
      }
    } catch (e) {
      if (!_refreshCompleter!.isCompleted) {
        _refreshCompleter!.completeError(e);
      }
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  // ============================================
  // HTTP METHODS
  // ============================================

  /// Build headers with auth token.
  ///
  /// 3.8: every call generates a fresh `x-request-id` and logs it via
  /// `dart:developer.log` so the mobile-side console + Crashlytics
  /// breadcrumbs carry the same id the server's pino-Loki line carries.
  /// On a "report this issue" path the user can copy a single id that
  /// resolves both halves of the trace.
  Map<String, String> _headers({
    bool isJson = true,
    String? idempotencyKey,
  }) {
    final headers = <String, String>{};
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey;
    }
    final requestId = _generateRequestId();
    headers['x-request-id'] = requestId;
    developer.log(
      'request_id=$requestId',
      name: 'ApiClient',
      level: 500, // INFO
    );
    return headers;
  }

  /// Execute a request with automatic token refresh on 401.
  Future<http.Response> _withAutoRefresh(
    Future<http.Response> Function() request,
  ) async {
    http.Response response;
    try {
      response = await request();
    } on TimeoutException {
      throw const ApiTimeoutException(
        'Request timed out. Please check your connection.',
      );
    } on SocketException catch (e) {
      throw ApiNetworkException('Network error: ${e.message}');
    }

    if (response.statusCode == 401 && _accessToken != null) {
      // 2.14: distinguish refresh failure from retry failure. Wrapping
      // both in one try/catch (the previous shape) treated a transient
      // network blip during the retry as if the refresh had failed —
      // tokens got cleared and the user was signed out. Now: only clear
      // tokens on a *refresh* failure; rethrow transport errors raised
      // during the retry so the caller sees the real cause.
      try {
        await refreshAccessToken();
      } catch (e) {
        _log('[ApiClient] Token refresh failed, signing out: $e');
        await clearTokens();
        return response;
      }
      // Refresh succeeded — retry the original request. Map transport
      // errors here to the same typed exceptions the first call uses so
      // upstream catch-blocks behave consistently.
      try {
        response = await request();
      } on TimeoutException {
        throw const ApiTimeoutException(
          'Request timed out. Please check your connection.',
        );
      } on SocketException catch (e) {
        throw ApiNetworkException('Network error: ${e.message}');
      }
    }

    return response;
  }

  /// Parse a response, throwing the matching [ApiException] subclass on
  /// any non-2xx status. The error envelope's `code` field (Phase 3) is
  /// preserved on the exception so the UI can branch on machine-readable
  /// error reasons.
  Map<String, dynamic> _parseResponse(http.Response response) {
    Map<String, dynamic> body;
    try {
      if (response.body.isEmpty) {
        body = <String, dynamic>{};
      } else {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        } else {
          throw ApiException.fromResponse(
            response.statusCode,
            redactSensitive(
              'Unexpected response format: expected a JSON object but got ${decoded.runtimeType}',
            ),
          );
        }
      }
    } on FormatException {
      throw ApiException.fromResponse(
        response.statusCode,
        'Invalid JSON in response body',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final code = body['code'] as String?;
    final message = redactSensitive(
      body['error'] as String? ??
          body['message'] as String? ??
          (response.statusCode == 429
              ? 'Too many requests. Please try again later.'
              : 'Request failed'),
    );

    int? retryAfterSeconds;
    if (response.statusCode == 429) {
      final retryAfter = response.headers['retry-after'];
      retryAfterSeconds = retryAfter != null ? int.tryParse(retryAfter) : null;
    }

    throw ApiException.fromResponse(
      response.statusCode,
      message,
      code: code ?? (response.statusCode == 429 ? 'rate_limited' : null),
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  static const _defaultTimeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(seconds: 120);

  /// Build a [Uri] for [baseUrl] + either a precomputed [path] or a list of
  /// [pathSegments] (each segment is percent-encoded by [Uri]). Exactly one
  /// of [path] / [pathSegments] must be supplied.
  Uri _buildUri({
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
  }) {
    assert(
      (path == null) != (pathSegments == null),
      'Provide exactly one of path or pathSegments',
    );

    final base = Uri.parse(baseUrl);
    if (pathSegments != null) {
      // Merge any segments already on baseUrl (e.g. when baseUrl ends in
      // `/api`) with the caller-provided segments. Empty strings are
      // dropped so trailing slashes don't produce `//` in the final URL.
      final merged = <String>[
        ...base.pathSegments.where((s) => s.isNotEmpty),
        ...pathSegments,
      ];
      return base.replace(
        pathSegments: merged,
        queryParameters: queryParams,
      );
    }

    // Legacy path mode — kept for hard-coded routes that contain no
    // interpolated user input. Accepts an absolute or relative path.
    final normalized = path!.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized')
        .replace(queryParameters: queryParams);
  }

  /// GET request.
  ///
  /// Provide either [path] (a hard-coded route with no interpolation) or
  /// [pathSegments] (preferred — segments are percent-encoded so user input
  /// can't escape the intended endpoint).
  Future<Map<String, dynamic>> get({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.get(uri, headers: _headers()).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// POST request with JSON body.
  ///
  /// Pass [idempotencyKey] for at-least-once retry safety on mutations
  /// dispatched from the offline queue.
  Future<Map<String, dynamic>> post({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.post(
        uri,
        headers: _headers(idempotencyKey: idempotencyKey),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// PUT request with JSON body.
  ///
  /// Pass [idempotencyKey] for at-least-once retry safety on mutations
  /// dispatched from the offline queue.
  Future<Map<String, dynamic>> put({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.put(
        uri,
        headers: _headers(idempotencyKey: idempotencyKey),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// PATCH request with JSON body.
  ///
  /// Pass [idempotencyKey] for at-least-once retry safety on mutations
  /// dispatched from the offline queue.
  Future<Map<String, dynamic>> patch({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.patch(
        uri,
        headers: _headers(idempotencyKey: idempotencyKey),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// DELETE request with optional JSON body.
  ///
  /// Pass [idempotencyKey] for at-least-once retry safety on mutations
  /// dispatched from the offline queue.
  Future<Map<String, dynamic>> delete({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.delete(
        uri,
        headers: _headers(idempotencyKey: idempotencyKey),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// Upload a file via multipart POST.
  ///
  /// Pass [idempotencyKey] for at-least-once retry safety on mutations
  /// dispatched from the offline queue.
  Future<Map<String, dynamic>> upload({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    required File file,
    required String fieldName,
    Map<String, String>? fields,
    String? idempotencyKey,
  }) async {
    final uri = _buildUri(path: path, pathSegments: pathSegments);

    Future<http.Response> doUpload() async {
      final request = http.MultipartRequest('POST', uri);

      // Use _accessToken at request time (not closure capture time)
      // so that after a token refresh, the new token is used.
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
        request.headers['Idempotency-Key'] = idempotencyKey;
      }

      if (fields != null) {
        request.fields.addAll(fields);
      }

      request.files.add(
        await http.MultipartFile.fromPath(fieldName, file.path),
      );

      final streamedResponse = await request.send().timeout(_uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    final response = await _withAutoRefresh(doUpload);
    return _parseResponse(response);
  }

  /// Clean up resources.
  void dispose() {
    _authStateController.close();
    _http.close();
  }
}

/// Riverpod provider for the API client.
///
/// Must be overridden in ProviderScope with an initialized ApiClient.
final apiClientProvider = Provider<ApiClient>((ref) {
  throw UnimplementedError(
    'apiClientProvider must be overridden in main() ProviderScope',
  );
});
