import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';
import '../services/documents_repository.dart';
import 'auth_provider.dart';

/// Provides the documents repository instance.
final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  return DocumentsRepository(ref.read(apiClientProvider));
});

/// Documents for a specific item.
final documentsForItemProvider =
    FutureProvider.family<List<Document>, String>((ref, itemId) async {
  ref.watch(currentUserProvider);

  final user = ref.read(currentUserProvider).value;
  if (user == null) return [];

  return ref.read(documentsRepositoryProvider).getDocumentsForItem(itemId);
});

/// All documents for the current user.
final allDocumentsProvider = FutureProvider<List<Document>>((ref) async {
  ref.watch(currentUserProvider);

  final user = ref.read(currentUserProvider).value;
  if (user == null) return [];

  return ref.read(documentsRepositoryProvider).getAllDocuments();
});

/// Upload a document and refresh the item's document list.
Future<Document> uploadDocument(
  WidgetRef ref, {
  required String itemId,
  required String filePath,
  required String fileName,
  required DocumentType type,
  String? mimeType,
}) async {
  final doc = await ref.read(documentsRepositoryProvider).uploadDocument(
        itemId: itemId,
        filePath: filePath,
        fileName: fileName,
        type: type,
        mimeType: mimeType,
      );

  // Refresh the item's documents
  ref.invalidate(documentsForItemProvider(itemId));

  return doc;
}

/// Delete a document and refresh the item's document list.
Future<void> deleteDocument(
  WidgetRef ref, {
  required String documentId,
  required String itemId,
}) async {
  await ref.read(documentsRepositoryProvider).deleteDocument(documentId);

  // Refresh the item's documents
  ref.invalidate(documentsForItemProvider(itemId));
}
