import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/warranty_purchases_repository.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import 'warranty_purchases_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late WarrantyPurchasesRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = WarrantyPurchasesRepository(mockClient);
  });

  /// Helper to build a valid warranty purchase JSON.
  Map<String, dynamic> purchaseJson({
    String id = 'purchase-1',
    String itemId = 'item-1',
    String userId = 'user-1',
    String status = 'active',
  }) {
    final now = DateTime.now().toIso8601String();
    final expiry =
        DateTime.now().add(const Duration(days: 365 * 3)).toIso8601String();
    return {
      'id': id,
      'item_id': itemId,
      'user_id': userId,
      'provider': 'SquareTrade',
      'plan_name': '3-Year Protection',
      'duration_months': 36,
      'starts_at': now,
      'expires_at': expiry,
      'price': 99.99,
      'deductible': 25.0,
      'purchase_date': now,
      'status': status,
      'created_at': now,
      'updated_at': now,
    };
  }

  group('WarrantyPurchasesRepository', () {
    group('getPurchases', () {
      test('calls correct endpoint with pagination params', () async {
        when(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getPurchases();

        final captured = verify(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['limit'], '100');
        expect(captured['page'], '1');
      });

      test('sends item_id and status query params when filters provided',
          () async {
        when(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getPurchases(itemId: 'item-42', status: 'active');

        final captured = verify(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['item_id'], 'item-42');
        expect(captured['status'], 'active');
      });

      test('does not send filters when not provided', () async {
        when(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getPurchases();

        final captured = verify(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured.containsKey('item_id'), isFalse);
        expect(captured.containsKey('status'), isFalse);
      });

      test('returns parsed list of purchases', () async {
        when(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {
              'data': [
                purchaseJson(id: 'purchase-1'),
                purchaseJson(id: 'purchase-2'),
              ],
            });

        final purchases = await repository.getPurchases();

        expect(purchases, hasLength(2));
        expect(purchases[0].id, 'purchase-1');
        expect(purchases[0].provider, 'SquareTrade');
        expect(purchases[1].id, 'purchase-2');
      });

      test('rethrows errors from API client', () async {
        when(mockClient.get(
          '/api/v1/warranty-purchases',
          queryParams: anyNamed('queryParams'),
        )).thenThrow(ApiException(500, 'Server error'));

        expect(
          () => repository.getPurchases(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('createPurchase', () {
      test('sends POST to correct endpoint and returns created purchase',
          () async {
        final now = DateTime.now();
        final purchase = WarrantyPurchase(
          id: 'temp-id',
          itemId: 'item-1',
          userId: 'user-1',
          provider: 'Asurion',
          planName: '2-Year Plan',
          durationMonths: 24,
          startsAt: now,
          expiresAt: now.add(const Duration(days: 365 * 2)),
          price: 79.99,
          deductible: 50.0,
          purchaseDate: now,
          status: WarrantyPurchaseStatus.active,
          createdAt: now,
          updatedAt: now,
        );

        when(mockClient.post(
          '/api/v1/warranty-purchases',
          body: anyNamed('body'),
        )).thenAnswer((_) async => {
              'data': purchaseJson(id: 'server-id'),
            });

        final created = await repository.createPurchase(purchase);

        expect(created.id, 'server-id');
        verify(mockClient.post(
          '/api/v1/warranty-purchases',
          body: anyNamed('body'),
        )).called(1);
      });
    });

    group('cancelPurchase', () {
      test('sends POST to cancel endpoint with reason', () async {
        when(mockClient.post(
          '/api/v1/warranty-purchases/purchase-1/cancel',
          body: anyNamed('body'),
        )).thenAnswer((_) async => {
              'data': purchaseJson(id: 'purchase-1', status: 'cancelled'),
            });

        final result = await repository.cancelPurchase(
          'purchase-1',
          reason: 'No longer needed',
        );

        expect(result.status, WarrantyPurchaseStatus.cancelled);

        final captured = verify(mockClient.post(
          '/api/v1/warranty-purchases/purchase-1/cancel',
          body: captureAnyNamed('body'),
        )).captured.single as Map<String, dynamic>;
        expect(captured['reason'], 'No longer needed');
      });

      test('sends POST to cancel endpoint without reason', () async {
        when(mockClient.post(
          '/api/v1/warranty-purchases/purchase-2/cancel',
          body: anyNamed('body'),
        )).thenAnswer((_) async => {
              'data': purchaseJson(id: 'purchase-2', status: 'cancelled'),
            });

        final result = await repository.cancelPurchase('purchase-2');

        expect(result.status, WarrantyPurchaseStatus.cancelled);
        verify(mockClient.post(
          '/api/v1/warranty-purchases/purchase-2/cancel',
          body: anyNamed('body'),
        )).called(1);
      });
    });
  });
}
