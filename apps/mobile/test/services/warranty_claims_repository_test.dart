import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/warranty_claims_repository.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import 'warranty_claims_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late WarrantyClaimsRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = WarrantyClaimsRepository(mockClient);
  });

  /// Helper to build a valid warranty claim JSON.
  Map<String, dynamic> claimJson({
    String id = 'claim-1',
    String itemId = 'item-1',
    String userId = 'user-1',
    String status = 'pending',
    double repairCost = 150.0,
    double amountSaved = 150.0,
  }) {
    return {
      'id': id,
      'user_id': userId,
      'item_id': itemId,
      'claim_date': '2026-01-15T00:00:00.000Z',
      'repair_cost': repairCost,
      'amount_saved': amountSaved,
      'status': status,
      'created_at': '2026-01-15T00:00:00.000Z',
      'updated_at': '2026-01-15T00:00:00.000Z',
    };
  }

  group('WarrantyClaimsRepository', () {
    group('getClaims', () {
      test('calls correct endpoint with pagination params', () async {
        when(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getClaims();

        final captured = verify(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['limit'], '100');
        expect(captured['page'], '1');
      });

      test('sends item_id query param when itemId is provided', () async {
        when(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getClaims(itemId: 'item-xyz');

        final captured = verify(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['item_id'], 'item-xyz');
      });

      test('does not send item_id when itemId is null', () async {
        when(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getClaims();

        final captured = verify(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured.containsKey('item_id'), isFalse);
      });

      test('returns parsed list of claims', () async {
        when(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {
              'data': [
                claimJson(id: 'claim-1'),
                claimJson(id: 'claim-2'),
              ],
            });

        final claims = await repository.getClaims();

        expect(claims, hasLength(2));
        expect(claims[0].id, 'claim-1');
        expect(claims[1].id, 'claim-2');
      });

      test('rethrows errors from API client', () async {
        when(mockClient.get(
          '/api/v1/warranty-claims',
          queryParams: anyNamed('queryParams'),
        )).thenThrow(ApiException(500, 'Server error'));

        expect(
          () => repository.getClaims(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('createClaim', () {
      test('sends POST to correct endpoint', () async {
        final now = DateTime.now();
        final claim = WarrantyClaim(
          id: 'temp-id',
          userId: 'user-1',
          itemId: 'item-1',
          claimDate: now,
          repairCost: 200.0,
          amountSaved: 200.0,
          createdAt: now,
          updatedAt: now,
        );

        when(mockClient.post(
          '/api/v1/warranty-claims',
          body: anyNamed('body'),
        )).thenAnswer((_) async => {
              'data': claimJson(id: 'created-1', repairCost: 200.0),
            });

        final created = await repository.createClaim(claim);

        expect(created.id, 'created-1');
        expect(created.repairCost, 200.0);
        verify(mockClient.post(
          '/api/v1/warranty-claims',
          body: anyNamed('body'),
        )).called(1);
      });
    });

    group('deleteClaim', () {
      test('sends DELETE to correct endpoint', () async {
        when(mockClient.delete('/api/v1/warranty-claims/claim-99'))
            .thenAnswer((_) async => {});

        await repository.deleteClaim('claim-99');

        verify(mockClient.delete('/api/v1/warranty-claims/claim-99')).called(1);
      });

      test('rethrows errors on delete failure', () async {
        when(mockClient.delete('/api/v1/warranty-claims/claim-1'))
            .thenThrow(ApiException(404, 'Not found'));

        expect(
          () => repository.deleteClaim('claim-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getSavings', () {
      test('calls correct endpoint and returns parsed data', () async {
        when(mockClient.get('/api/v1/warranty-claims/savings'))
            .thenAnswer((_) async => {
                  'data': {
                    'total_saved': 450.0,
                    'claim_count': 4,
                    'average_saved': 112.5,
                  },
                });

        final savings = await repository.getSavings();

        expect(savings['total_saved'], 450.0);
        expect(savings['claim_count'], 4);
        verify(mockClient.get('/api/v1/warranty-claims/savings')).called(1);
      });
    });

    group('getSavingsFeed', () {
      test('sends limit query param and calls correct endpoint', () async {
        when(mockClient.get(
          '/api/v1/warranty-claims/feed',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {
              'data': [
                {'amount': 100.0, 'category': 'refrigerator'},
                {'amount': 250.0, 'category': 'hvac'},
              ],
            });

        final feed = await repository.getSavingsFeed(limit: 5);

        expect(feed, hasLength(2));

        final captured = verify(mockClient.get(
          '/api/v1/warranty-claims/feed',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['limit'], '5');
      });

      test('uses default limit of 10 when not specified', () async {
        when(mockClient.get(
          '/api/v1/warranty-claims/feed',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getSavingsFeed();

        final captured = verify(mockClient.get(
          '/api/v1/warranty-claims/feed',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['limit'], '10');
      });
    });
  });
}
