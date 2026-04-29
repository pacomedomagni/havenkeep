import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';

/// Result of an OAuth code-grant flow used by the email scanner.
///
/// The mobile client never holds the access token. It forwards [code] +
/// [redirectUri] to the HavenKeep API which exchanges them for the access
/// and refresh tokens server-side and stores the refresh token encrypted.
class EmailOAuthCode {
  const EmailOAuthCode({required this.code, required this.redirectUri});

  final String code;
  final String redirectUri;
}

/// Drives OAuth authorization-code flows for the email scanner.
class EmailOAuthService {
  final Ref _ref;

  EmailOAuthService(this._ref);

  /// Get a Gmail OAuth `code` via the system browser. The redirect URI is
  /// the custom scheme the platform OAuth app is registered with.
  Future<EmailOAuthCode> getGmailAuthorizationCode() async {
    final config = _ref.read(environmentConfigProvider);
    if (config.googleServerClientId.isEmpty) {
      throw StateError('Google OAuth client is not configured');
    }
    if (config.gmailRedirectUri.isEmpty) {
      throw StateError('Gmail OAuth redirect URI is not configured');
    }

    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': config.googleServerClientId,
      'response_type': 'code',
      'redirect_uri': config.gmailRedirectUri,
      'scope': 'email https://www.googleapis.com/auth/gmail.readonly',
      'access_type': 'offline',
      'prompt': 'consent',
    });

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: Uri.parse(config.gmailRedirectUri).scheme,
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw StateError('Gmail authorization failed');
      }

      return EmailOAuthCode(code: code, redirectUri: config.gmailRedirectUri);
    } catch (e) {
      debugPrint('[EmailOAuth] Gmail authorize failed: $e');
      rethrow;
    }
  }

  /// Get an Outlook OAuth `code` via the system browser. Mobile forwards
  /// `code` + `redirectUri` to the API, which performs the token exchange
  /// using its server-side `client_secret`. The Azure AD app must therefore
  /// be configured as a confidential/web client (NOT public). PKCE is
  /// intentionally NOT sent — the API never sees a `code_verifier`, and
  /// Microsoft would reject the redemption if PKCE was advertised here but
  /// not completed at the token endpoint.
  Future<EmailOAuthCode> getOutlookAuthorizationCode() async {
    final config = _ref.read(environmentConfigProvider);
    if (config.outlookClientId.isEmpty || config.outlookRedirectUri.isEmpty) {
      throw StateError('Outlook OAuth is not configured');
    }

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
      },
    );

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: Uri.parse(config.outlookRedirectUri).scheme,
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw StateError('Outlook authorization failed');
      }

      return EmailOAuthCode(code: code, redirectUri: config.outlookRedirectUri);
    } catch (e) {
      debugPrint('[EmailOAuth] Outlook authorize failed: $e');
      rethrow;
    }
  }
}

final emailOAuthServiceProvider = Provider<EmailOAuthService>((ref) {
  return EmailOAuthService(ref);
});
