import 'package:api_client/api_client.dart';
import '../exceptions/network_exceptions.dart';

class PartnersRepository {
  final ApiClient _client;

  PartnersRepository(this._client);

  /// Activate a partner gift using activation code or gift ID
  Future<Map<String, dynamic>> activateGift(String giftId) async {
    try {
      return await _client.post('/api/v1/partners/gifts/$giftId/activate');
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

  /// Get gift details by ID (for preview before activation)
  Future<Map<String, dynamic>> getGiftDetails(String giftId) async {
    try {
      return await _client.get('/api/v1/partners/gifts/$giftId/public');
    } on ApiException catch (e) {
      throw NetworkException(
        e.message,
        statusCode: e.statusCode,
      );
    } on Exception catch (e) {
      if (e is NetworkException) rethrow;
      throw NetworkException('Failed to fetch gift details: $e');
    }
  }

  /// Verify activation code and get gift ID
  Future<Map<String, dynamic>> verifyActivationCode(String code) async {
    try {
      return await _client.post(
        '/api/v1/partners/gifts/verify-code',
        body: {'activation_code': code},
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
}
