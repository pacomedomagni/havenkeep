import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// S1-H: per-attempt nonce for Apple Sign-In replay protection.
///
/// Apple's SDK takes the SHA-256 hex of a random value as `nonce` input
/// and bakes the same hex into the resulting ID token's `nonce` claim.
/// The client sends the *unhashed* value to the API; the server hashes
/// again and verifies the result against the token claim.
///
/// Use [AppleSignInNonce.generate] at the start of each sign-in attempt;
/// pass [hashed] to `SignInWithApple.getAppleIDCredential(nonce:)` and
/// [raw] in the request body.
class AppleSignInNonce {
  AppleSignInNonce._({required this.raw, required this.hashed});

  /// 32-byte url-safe random string. Sent to the API.
  final String raw;

  /// SHA-256(raw) as lowercase hex. Sent to Apple's SDK.
  final String hashed;

  static AppleSignInNonce generate() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final raw = base64UrlEncode(bytes).replaceAll('=', '');
    final hashed = sha256.convert(utf8.encode(raw)).toString();
    return AppleSignInNonce._(raw: raw, hashed: hashed);
  }
}
