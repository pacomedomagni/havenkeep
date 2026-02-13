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

  ApiException(this.statusCode, this.message, {this.code});

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

/// HTTP API client for the HavenKeep Express backend.
///
/// Manages JWT tokens (access + refresh) in secure storage,
/// auto-refreshes expired access tokens, and provides typed
/// convenience methods for REST operations.
class ApiClient {
  final String baseUrl;
  final http.Client _http;
  final FlutterSecureStorage _storage;

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
  })  : _http = httpClient ?? http.Client(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

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
          debugPrint('[ApiClient] Stored access token is expired, refreshing...');
          try {
            await refreshAccessToken()
                .timeout(const Duration(seconds: 10));
            return true;
          } catch (e) {
            debugPrint('[ApiClient] Token refresh failed during restore: $e');
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
          debugPrint('[ApiClient] Token refresh failed during restore: $e');
          await clearTokens();
          return false;
        }
      }

      return false;
    } catch (e) {
      debugPrint('[ApiClient] Failed to restore session: $e');
      return false;
    }
  }

  /// Decode a JWT and check if the `exp` claim indicates the token is expired.
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
      debugPrint('[ApiClient] Failed to decode JWT for expiration check: $e');
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
        Uri.parse('$baseUrl/api/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = data['accessToken'] as String;
        await _storage.write(key: _keyAccessToken, value: _accessToken!);
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
    var response = await request();

    if (response.statusCode == 401 && _accessToken != null) {
      try {
        await refreshAccessToken();
        // Retry with new token
        response = await request();
      } catch (e) {
        // Refresh failed — log and return the original 401
        debugPrint('[ApiClient] Token refresh failed: $e');
      }
    }

    return response;
  }

  /// Parse a response, throwing [ApiException] on error.
  Map<String, dynamic> _parseResponse(http.Response response) {
    final body = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw ApiException(
      response.statusCode,
      body['error'] as String? ??
          body['message'] as String? ??
          'Request failed',
      code: body['code'] as String?,
    );
  }

  /// GET request.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
    final response = await _withAutoRefresh(
      () => _http.get(uri, headers: _headers()),
    );
    return _parseResponse(response);
  }

  /// POST request with JSON body.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _withAutoRefresh(
      () => _http.post(
        Uri.parse('$baseUrl$path'),
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    return _parseResponse(response);
  }

  /// PUT request with JSON body.
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _withAutoRefresh(
      () => _http.put(
        Uri.parse('$baseUrl$path'),
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    return _parseResponse(response);
  }

  /// PATCH request with JSON body.
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _withAutoRefresh(
      () => _http.patch(
        Uri.parse('$baseUrl$path'),
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    return _parseResponse(response);
  }

  /// DELETE request with optional JSON body.
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _withAutoRefresh(
      () => _http.delete(
        Uri.parse('$baseUrl$path'),
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    return _parseResponse(response);
  }

  /// Upload a file via multipart POST.
  Future<Map<String, dynamic>> upload(
    String path, {
    required File file,
    required String fieldName,
    Map<String, String>? fields,
  }) async {
    Future<http.Response> doUpload() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl$path'),
      );

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

      final streamedResponse = await request.send();
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

/// Returns the current authenticated user's ID, or null if not logged in.
String? getCurrentUserId() {
  // This is accessed via the global ApiClient instance
  // For backward compatibility, we provide this as a standalone function
  return _globalApiClient?.currentUserId;
}

/// Returns the current authenticated user's ID.
/// Throws [StateError] if not logged in.
String requireCurrentUserId() {
  final id = getCurrentUserId();
  if (id == null) {
    throw StateError('User is not authenticated');
  }
  return id;
}

/// Internal reference to the global ApiClient for the standalone functions.
ApiClient? _globalApiClient;

/// Set the global ApiClient reference (called from main.dart).
void setGlobalApiClient(ApiClient client) {
  _globalApiClient = client;
}
