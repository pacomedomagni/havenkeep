import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/environment_config.dart';
import '../services/secure_storage_service.dart';
import '../exceptions/network_exceptions.dart';

class PartnersRepository {
  final SecureStorageService _storageService = SecureStorageService();

  /// Activate a partner gift using activation code or gift ID
  Future<Map<String, dynamic>> activateGift(String giftId) async {
    try {
      final token = await _storageService.getAccessToken();
      if (token == null) {
        throw NetworkException('Not authenticated');
      }

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/partners/gifts/$giftId/activate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        throw NetworkException(
          data['message'] ?? 'Failed to activate gift',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is NetworkException) rethrow;
      throw NetworkException('Failed to activate gift: $e');
    }
  }

  /// Get gift details by ID (for preview before activation)
  Future<Map<String, dynamic>> getGiftDetails(String giftId) async {
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/partners/gifts/$giftId/public'),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        throw NetworkException(
          data['message'] ?? 'Failed to fetch gift details',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is NetworkException) rethrow;
      throw NetworkException('Failed to fetch gift details: $e');
    }
  }

  /// Verify activation code and get gift ID
  Future<Map<String, dynamic>> verifyActivationCode(String code) async {
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/partners/gifts/verify-code'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'activation_code': code,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        throw NetworkException(
          data['message'] ?? 'Invalid activation code',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is NetworkException) rethrow;
      throw NetworkException('Failed to verify activation code: $e');
    }
  }
}
