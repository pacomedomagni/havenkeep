import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Exception thrown when an API request fails.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final int? retryAfterSeconds;

  ApiException(this.statusCode, this.message, {this.code, this.retryAfterSeconds});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;
  bool get isServerError => statusCode >= 500;

  @override
  String toString() => 'ApiException($statusCode): $message';
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
/// remote sink (Sentry, Datadog), so leaking access tokens in those breadcrumbs
/// would let an attacker who reads the log replay full sessions.
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
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
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
          } catch (e) {
            _log('[ApiClient] Token refresh failed during restore: $e');
            await clearTokens();
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
        } catch (e) {
          _log('[ApiClient] Token refresh failed during restore: $e');
          await clearTokens();
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
        throw ApiException(401, 'No refresh token available');
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
          throw ApiException(
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
        final error = ApiException(401, 'Session expired. Please sign in again.');
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
  Map<String, String> _headers({bool isJson = true}) {
    final headers = <String, String>{};
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
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
      throw ApiException(0, 'Request timed out. Please check your connection.');
    } on SocketException catch (e) {
      throw ApiException(0, 'Network error: ${e.message}');
    }

    if (response.statusCode == 401 && _accessToken != null) {
      try {
        await refreshAccessToken();
        // Retry with new token
        response = await request();
      } catch (e) {
        // Refresh failed — clear tokens so the user isn't stuck half-authenticated
        _log('[ApiClient] Token refresh failed, signing out: $e');
        await clearTokens();
      }
    }

    return response;
  }

  /// Parse a response, throwing [ApiException] on error.
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
          throw ApiException(
            response.statusCode,
            redactSensitive(
              'Unexpected response format: expected a JSON object but got ${decoded.runtimeType}',
            ),
          );
        }
      }
    } on FormatException {
      throw ApiException(
        response.statusCode,
        'Invalid JSON in response body',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    if (response.statusCode == 429) {
      final retryAfter = response.headers['retry-after'];
      final retryAfterSeconds = retryAfter != null ? int.tryParse(retryAfter) : null;
      throw ApiException(
        429,
        redactSensitive(
          body['message'] as String? ?? 'Too many requests. Please try again later.',
        ),
        code: 'rate_limited',
        retryAfterSeconds: retryAfterSeconds,
      );
    }

    throw ApiException(
      response.statusCode,
      redactSensitive(
        body['error'] as String? ??
            body['message'] as String? ??
            'Request failed',
      ),
      code: body['code'] as String?,
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
  Future<Map<String, dynamic>> post({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.post(
        uri,
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// PUT request with JSON body.
  Future<Map<String, dynamic>> put({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.put(
        uri,
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// PATCH request with JSON body.
  Future<Map<String, dynamic>> patch({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.patch(
        uri,
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// DELETE request with optional JSON body.
  Future<Map<String, dynamic>> delete({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(
      path: path,
      pathSegments: pathSegments,
      queryParams: queryParams,
    );
    final response = await _withAutoRefresh(
      () => _http.delete(
        uri,
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_defaultTimeout),
    );
    return _parseResponse(response);
  }

  /// Upload a file via multipart POST.
  Future<Map<String, dynamic>> upload({
    @Deprecated(
      'Use pathSegments to avoid URL injection. Only acceptable for hard-coded routes with no interpolated values.',
    )
    String? path,
    List<String>? pathSegments,
    required File file,
    required String fieldName,
    Map<String, String>? fields,
  }) async {
    final uri = _buildUri(path: path, pathSegments: pathSegments);

    Future<http.Response> doUpload() async {
      final request = http.MultipartRequest('POST', uri);

      // Use _accessToken at request time (not closure capture time)
      // so that after a token refresh, the new token is used.
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
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
