import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/environment_config.dart';
import '../../main.dart';

/// Handles OAuth flows to retrieve access tokens for email scanning.
class EmailOAuthService {
  final Ref _ref;

  EmailOAuthService(this._ref);

  /// Get a Gmail access token with read-only mailbox scope.
  Future<String> getGmailAccessToken() async {
    final googleSignIn = GoogleSignIn(
      scopes: const [
        'email',
        'https://www.googleapis.com/auth/gmail.readonly',
      ],
    );

    final account = await googleSignIn.signIn();
    if (account == null) {
      throw StateError('Gmail sign-in cancelled');
    }

    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Failed to obtain Gmail access token');
    }

    return token;
  }

  /// Get an Outlook access token via OAuth PKCE.
  Future<String> getOutlookAccessToken() async {
    final config = _ref.read(environmentConfigProvider);
    if (config.outlookClientId.isEmpty || config.outlookRedirectUri.isEmpty) {
      throw StateError('Outlook OAuth is not configured');
    }

    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _createCodeChallenge(codeVerifier);

    final tenant = config.outlookTenant.isNotEmpty ? config.outlookTenant : 'common';
    final authUri = Uri.https(
      'login.microsoftonline.com',
      '/$tenant/oauth2/v2.0/authorize',
      {
        'client_id': config.outlookClientId,
        'response_type': 'code',
        'redirect_uri': config.outlookRedirectUri,
        'response_mode': 'query',
        'scope': 'offline_access https://graph.microsoft.com/Mail.Read',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );

    final result = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: Uri.parse(config.outlookRedirectUri).scheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('Outlook authorization failed');
    }

    final tokenUri = Uri.https(
      'login.microsoftonline.com',
      '/$tenant/oauth2/v2.0/token',
    );

    final tokenResponse = await http.post(
      tokenUri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.outlookClientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.outlookRedirectUri,
        'code_verifier': codeVerifier,
        'scope': 'offline_access https://graph.microsoft.com/Mail.Read',
      },
    );

    if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
      debugPrint('[EmailOAuth] Outlook token exchange failed: ${tokenResponse.statusCode}');
      throw StateError('Outlook token exchange failed');
    }

    final json = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Outlook access token missing');
    }

    return accessToken;
  }

  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _createCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}

final emailOAuthServiceProvider = Provider<EmailOAuthService>((ref) {
  return EmailOAuthService(ref);
});
