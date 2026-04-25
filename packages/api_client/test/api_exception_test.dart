import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the sealed [ApiException] hierarchy (P002+).
///
/// The factory must mint the right subclass for every status code we
/// care about, the legacy convenience flags must continue to mirror the
/// subclass identity, and a switch over the sealed type must be
/// exhaustive (the `default` branch should be unreachable).
void main() {
  group('ApiException.fromResponse', () {
    test('401 -> ApiAuthRequiredException', () {
      final e = ApiException.fromResponse(401, 'unauth');
      expect(e, isA<ApiAuthRequiredException>());
      expect(e.isUnauthorized, isTrue);
    });

    test('403 -> ApiForbiddenException', () {
      final e = ApiException.fromResponse(403, 'nope', code: 'premium_required');
      expect(e, isA<ApiForbiddenException>());
      expect(e.isForbidden, isTrue);
      expect(e.code, 'premium_required');
    });

    test('404 -> ApiNotFoundException', () {
      final e = ApiException.fromResponse(404, 'gone');
      expect(e, isA<ApiNotFoundException>());
      expect(e.isNotFound, isTrue);
    });

    test('400 / 422 -> ApiValidationException', () {
      expect(
        ApiException.fromResponse(400, 'bad'),
        isA<ApiValidationException>(),
      );
      expect(
        ApiException.fromResponse(422, 'invalid'),
        isA<ApiValidationException>(),
      );
    });

    test('409 -> ApiConflictException', () {
      final e = ApiException.fromResponse(409, 'conflict');
      expect(e, isA<ApiConflictException>());
      expect(e.isConflict, isTrue);
    });

    test('429 -> ApiRateLimitedException with retryAfter', () {
      final e = ApiException.fromResponse(
        429,
        'slow down',
        code: 'rate_limited',
        retryAfterSeconds: 12,
      );
      expect(e, isA<ApiRateLimitedException>());
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfterSeconds, 12);
    });

    test('5xx -> ApiServerException', () {
      for (final code in [500, 502, 503, 504]) {
        final e = ApiException.fromResponse(code, 'boom');
        expect(e, isA<ApiServerException>(), reason: 'status=$code');
        expect(e.isServerError, isTrue, reason: 'status=$code');
      }
    });

    test('unknown 4xx -> ApiUnknownException', () {
      final e = ApiException.fromResponse(418, 'teapot');
      expect(e, isA<ApiUnknownException>());
    });
  });

  group('Network/Timeout subclasses', () {
    test('ApiNetworkException carries statusCode 0', () {
      const e = ApiNetworkException('offline');
      expect(e.statusCode, 0);
      expect(e.message, 'offline');
    });

    test('ApiTimeoutException carries statusCode 0', () {
      const e = ApiTimeoutException('timed out');
      expect(e.statusCode, 0);
    });
  });

  group('Sealed switch exhaustiveness', () {
    String classify(ApiException e) => switch (e) {
          ApiAuthRequiredException() => 'auth',
          ApiForbiddenException() => 'forbidden',
          ApiNotFoundException() => 'notfound',
          ApiValidationException() => 'validation',
          ApiConflictException() => 'conflict',
          ApiRateLimitedException() => 'ratelimit',
          ApiServerException() => 'server',
          ApiNetworkException() => 'network',
          ApiTimeoutException() => 'timeout',
          ApiUnknownException() => 'unknown',
        };

    test('every subclass is reachable by an exhaustive switch', () {
      expect(classify(ApiException.fromResponse(401, '')), 'auth');
      expect(classify(ApiException.fromResponse(403, '')), 'forbidden');
      expect(classify(ApiException.fromResponse(404, '')), 'notfound');
      expect(classify(ApiException.fromResponse(400, '')), 'validation');
      expect(classify(ApiException.fromResponse(409, '')), 'conflict');
      expect(classify(ApiException.fromResponse(429, '')), 'ratelimit');
      expect(classify(ApiException.fromResponse(500, '')), 'server');
      expect(classify(ApiException.fromResponse(418, '')), 'unknown');
      expect(classify(const ApiNetworkException('')), 'network');
      expect(classify(const ApiTimeoutException('')), 'timeout');
    });
  });

  group('redactSensitive', () {
    test('strips Bearer tokens', () {
      final out = redactSensitive('Authorization: Bearer abc.def.ghi');
      expect(out, contains('Bearer [REDACTED]'));
      expect(out, isNot(contains('abc.def.ghi')));
    });

    test('strips JWT-shaped strings', () {
      final out = redactSensitive(
        'token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.signature_here',
      );
      expect(out, contains('[REDACTED_JWT]'));
    });
  });
}
