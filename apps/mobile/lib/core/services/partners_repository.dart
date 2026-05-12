import 'package:api_client/api_client.dart';
import '../exceptions/network_exceptions.dart';

class PartnersRepository {
  final ApiClient _client;

  PartnersRepository(this._client);

  /// Activate a partner gift using activation code or gift ID
  Future<Map<String, dynamic>> activateGift(String giftId) async {
    try {
      return await _client.post(
        pathSegments: ['api', 'v1', 'partners', 'gifts', giftId, 'activate'],
      );
    } on ApiException catch (e) {
      throw NetworkException(
        e.message,
        statusCode: e.statusCode,
      );
    } on Exception catch (e) {
      if (e is NetworkException) rethrow;
      throw NetworkException('Failed to activate gift: $e');
    }
  }

  /// Verify activation code and get gift ID. The backend requires the
  /// homebuyer email as a second factor (Ch09-FlowC-T-C3) — without it the
  /// route is a code-enumeration oracle.
  Future<Map<String, dynamic>> verifyActivationCode({
    required String code,
    required String homebuyerEmail,
  }) async {
    try {
      return await _client.post(
        pathSegments: const ['api', 'v1', 'partners', 'gifts', 'verify-code'],
        body: {
          'activation_code': code,
          'homebuyer_email': homebuyerEmail,
        },
      );
    } on ApiException catch (e) {
      throw NetworkException(
        e.message,
        statusCode: e.statusCode,
      );
    } on Exception catch (e) {
      if (e is NetworkException) rethrow;
      throw NetworkException('Failed to verify activation code: $e');
    }
  }

  /// All partner gifts where the current user is the recipient
  /// (activated). Returns the raw JSON list — the screen layer maps this to
  /// its display model.
  Future<List<Map<String, dynamic>>> getMyGifts() async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'users', 'me', 'gifts'],
      );
      return List<Map<String, dynamic>>.from(data['data'] as List);
    } on ApiException catch (e) {
      throw NetworkException(
        e.message,
        statusCode: e.statusCode,
      );
    } on Exception catch (e) {
      if (e is NetworkException) rethrow;
      throw NetworkException('Failed to fetch recent gifts: $e');
    }
  }
}
