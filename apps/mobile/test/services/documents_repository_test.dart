import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/documents_repository.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import 'documents_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late DocumentsRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = DocumentsRepository(mockClient);
  });

  /// Helper to build a valid document JSON response.
  Map<String, dynamic> documentJson({
    String id = 'doc-1',
    String itemId = 'item-1',
    String userId = 'user-1',
    String type = 'receipt',
  }) {
    return {
      'id': id,
      'item_id': itemId,
      'user_id': userId,
      'type': type,
      'file_url': 'https://example.com/$id.pdf',
      'file_name': '$id.pdf',
      'file_size': 1024,
      'mime_type': 'application/pdf',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    };
  }

  group('DocumentsRepository', () {
    group('getDocumentsForItem', () {
      test('calls correct endpoint with item_id query param', () async {
        when(mockClient.get(
          '/api/v1/documents',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getDocumentsForItem('item-abc');

        final captured = verify(mockClient.get(
          '/api/v1/documents',
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['item_id'], 'item-abc');
      });

      test('returns parsed list of documents', () async {
        when(mockClient.get(
          '/api/v1/documents',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {
              'data': [
                documentJson(id: 'doc-1', itemId: 'item-1'),
                documentJson(id: 'doc-2', itemId: 'item-1'),
              ],
            });

        final docs = await repository.getDocumentsForItem('item-1');

        expect(docs, hasLength(2));
        expect(docs[0].id, 'doc-1');
        expect(docs[0].itemId, 'item-1');
        expect(docs[1].id, 'doc-2');
      });

      test('returns empty list when no documents exist', () async {
        when(mockClient.get(
          '/api/v1/documents',
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        final docs = await repository.getDocumentsForItem('item-99');

        expect(docs, isEmpty);
      });

      test('rethrows errors from API client', () async {
        when(mockClient.get(
          '/api/v1/documents',
          queryParams: anyNamed('queryParams'),
        )).thenThrow(ApiException(500, 'Server error'));

        expect(
          () => repository.getDocumentsForItem('item-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getAllDocuments', () {
      test('calls correct endpoint without query params', () async {
        when(mockClient.get('/api/v1/documents'))
            .thenAnswer((_) async => {'data': []});

        await repository.getAllDocuments();

        verify(mockClient.get('/api/v1/documents')).called(1);
      });

      test('returns all documents for the current user', () async {
        when(mockClient.get('/api/v1/documents'))
            .thenAnswer((_) async => {
                  'data': [
                    documentJson(id: 'doc-1', itemId: 'item-1'),
                    documentJson(id: 'doc-2', itemId: 'item-2'),
                    documentJson(id: 'doc-3', itemId: 'item-3'),
                  ],
                });

        final docs = await repository.getAllDocuments();

        expect(docs, hasLength(3));
        expect(docs[0].id, 'doc-1');
        expect(docs[2].id, 'doc-3');
      });
    });

    group('deleteDocument', () {
      test('calls DELETE with correct document ID', () async {
        when(mockClient.delete('/api/v1/documents/doc-42'))
            .thenAnswer((_) async => {});

        await repository.deleteDocument('doc-42');

        verify(mockClient.delete('/api/v1/documents/doc-42')).called(1);
      });

      test('rethrows errors on delete failure', () async {
        when(mockClient.delete('/api/v1/documents/doc-1'))
            .thenThrow(ApiException(404, 'Not found'));

        expect(
          () => repository.deleteDocument('doc-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });
  });
}
