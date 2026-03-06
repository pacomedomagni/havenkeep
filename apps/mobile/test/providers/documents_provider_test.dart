import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/documents_provider.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/services/documents_repository.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'documents_provider_test.mocks.dart';

/// Test notifier that immediately resolves to a fixed user value.
class _TestCurrentUserNotifier extends CurrentUserNotifier {
  final User? _user;
  _TestCurrentUserNotifier(this._user);

  @override
  Future<User?> build() async => _user;
}

@GenerateMocks([DocumentsRepository])
void main() {
  late MockDocumentsRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockDocumentsRepository();
  });

  tearDown(() {
    container.dispose();
  });

  ProviderContainer createContainer({bool authenticated = true}) {
    final testUser = authenticated
        ? TestHelpers.createTestUser(id: TestHelpers.testUserId)
        : null;

    return ProviderContainer(
      overrides: [
        documentsRepositoryProvider.overrideWithValue(mockRepository),
        currentUserProvider.overrideWith(
          () => _TestCurrentUserNotifier(testUser),
        ),
      ],
    );
  }

  group('documentsForItemProvider', () {
    test('returns empty list when user is not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final docs = await container.read(
        documentsForItemProvider('item-1').future,
      );

      expect(docs, isEmpty);
      verifyNever(mockRepository.getDocumentsForItem(any));
    });

    test('fetches documents for a specific item', () async {
      when(mockRepository.getDocumentsForItem('item-1'))
          .thenAnswer((_) async => [
                TestHelpers.createTestDocument(id: 'doc-1', itemId: 'item-1'),
                TestHelpers.createTestDocument(id: 'doc-2', itemId: 'item-1'),
              ]);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final docs = await container.read(
        documentsForItemProvider('item-1').future,
      );

      expect(docs, hasLength(2));
      verify(mockRepository.getDocumentsForItem('item-1')).called(1);
    });

    test('returns list of documents with correct fields', () async {
      final testDoc = TestHelpers.createTestDocument(
        id: 'doc-abc',
        itemId: 'item-1',
        type: DocumentType.receipt,
        fileUrl: 'https://example.com/doc.pdf',
      );
      when(mockRepository.getDocumentsForItem('item-1'))
          .thenAnswer((_) async => [testDoc]);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final docs = await container.read(
        documentsForItemProvider('item-1').future,
      );

      expect(docs, hasLength(1));
      expect(docs[0].id, 'doc-abc');
      expect(docs[0].itemId, 'item-1');
      expect(docs[0].type, DocumentType.receipt);
    });

    test('uses separate family key per item', () async {
      when(mockRepository.getDocumentsForItem('item-1'))
          .thenAnswer((_) async => [
                TestHelpers.createTestDocument(id: 'doc-1', itemId: 'item-1'),
              ]);
      when(mockRepository.getDocumentsForItem('item-2'))
          .thenAnswer((_) async => [
                TestHelpers.createTestDocument(id: 'doc-2', itemId: 'item-2'),
                TestHelpers.createTestDocument(id: 'doc-3', itemId: 'item-2'),
              ]);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final docs1 = await container.read(
        documentsForItemProvider('item-1').future,
      );
      final docs2 = await container.read(
        documentsForItemProvider('item-2').future,
      );

      expect(docs1, hasLength(1));
      expect(docs2, hasLength(2));
    });

    test('propagates error on fetch failure', () async {
      when(mockRepository.getDocumentsForItem('item-1'))
          .thenThrow(Exception('Network error'));

      container = createContainer();
      await container.read(currentUserProvider.future);

      expect(
        () => container.read(documentsForItemProvider('item-1').future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('allDocumentsProvider', () {
    test('returns empty list when user is not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final docs = await container.read(allDocumentsProvider.future);

      expect(docs, isEmpty);
      verifyNever(mockRepository.getAllDocuments());
    });

    test('fetches all documents when authenticated', () async {
      when(mockRepository.getAllDocuments()).thenAnswer((_) async => [
            TestHelpers.createTestDocument(id: 'doc-1'),
            TestHelpers.createTestDocument(id: 'doc-2'),
            TestHelpers.createTestDocument(id: 'doc-3'),
          ]);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final docs = await container.read(allDocumentsProvider.future);

      expect(docs, hasLength(3));
      verify(mockRepository.getAllDocuments()).called(1);
    });

    test('returns empty list when user has no documents', () async {
      when(mockRepository.getAllDocuments()).thenAnswer((_) async => []);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final docs = await container.read(allDocumentsProvider.future);

      expect(docs, isEmpty);
    });

    test('propagates error on fetch failure', () async {
      when(mockRepository.getAllDocuments())
          .thenThrow(Exception('Server error'));

      container = createContainer();
      await container.read(currentUserProvider.future);

      expect(
        () => container.read(allDocumentsProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });
}
