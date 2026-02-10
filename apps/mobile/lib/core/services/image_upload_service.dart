import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_client/supabase_client.dart';

import '../utils/file_validator.dart';
import 'logging_service.dart';

/// Handles image uploads to Supabase Storage (avatars, item photos).
///
/// All uploads are validated before being sent to storage to prevent:
/// - Malicious files
/// - Files that are too large
/// - Wrong file types
class ImageUploadService {
  final Ref _ref;

  ImageUploadService(this._ref);

  /// Upload a profile photo for the given user.
  ///
  /// Returns the public URL of the uploaded avatar.
  ///
  /// Validates the file before upload to ensure:
  /// - File size is within limits (10MB max)
  /// - File type is allowed (JPEG, PNG, WebP)
  /// - File content matches the claimed type
  /// - No malicious content
  ///
  /// Throws [FileUploadException] if validation fails.
  Future<String> uploadProfilePhoto({
    required String userId,
    required File imageFile,
  }) async {
    // CRITICAL: Validate file before upload
    LoggingService.debug('Validating profile photo upload', {
      'userId': userId,
      'filePath': imageFile.path,
      'fileSize': await imageFile.length(),
    });

    await FileValidator.validateImage(imageFile);

    LoggingService.info('Profile photo validated, uploading', {
      'userId': userId,
      'fileSize': FileValidator.formatFileSize(await imageFile.length()),
    });

    final client = _ref.read(supabaseClientProvider);
    final ext = p.extension(imageFile.path).replaceAll('.', '');
    final storagePath = '$userId/avatar.$ext';

    debugPrint('[ImageUpload] Uploading avatar to: $storagePath');

    // Upload (upsert to overwrite existing avatar)
    await client.storage.from('avatars').upload(
      storagePath,
      imageFile,
      fileOptions: const FileOptions(
        cacheControl: '3600',
        upsert: true,
      ),
    );

    // Get the public URL
    final publicUrl = client.storage.from('avatars').getPublicUrl(storagePath);

    LoggingService.info('Profile photo uploaded successfully', {
      'userId': userId,
      'url': publicUrl,
    });

    debugPrint('[ImageUpload] Avatar uploaded: $publicUrl');
    return publicUrl;
  }

  /// Upload an item product image.
  ///
  /// Returns the public URL of the uploaded image.
  ///
  /// Validates the file before upload (same as profile photo).
  ///
  /// Throws [FileUploadException] if validation fails.
  Future<String> uploadItemImage({
    required String itemId,
    required File imageFile,
  }) async {
    // CRITICAL: Validate file before upload
    LoggingService.debug('Validating item image upload', {
      'itemId': itemId,
      'filePath': imageFile.path,
      'fileSize': await imageFile.length(),
    });

    await FileValidator.validateImage(imageFile);

    LoggingService.info('Item image validated, uploading', {
      'itemId': itemId,
      'fileSize': FileValidator.formatFileSize(await imageFile.length()),
    });

    final client = _ref.read(supabaseClientProvider);
    final ext = p.extension(imageFile.path).replaceAll('.', '');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$itemId/$timestamp.$ext';

    debugPrint('[ImageUpload] Uploading item image to: $storagePath');

    await client.storage.from('item-images').upload(
      storagePath,
      imageFile,
      fileOptions: const FileOptions(
        cacheControl: '3600',
        upsert: false,
      ),
    );

    final publicUrl =
        client.storage.from('item-images').getPublicUrl(storagePath);

    LoggingService.info('Item image uploaded successfully', {
      'itemId': itemId,
      'url': publicUrl,
    });

    debugPrint('[ImageUpload] Item image uploaded: $publicUrl');
    return publicUrl;
  }
}

/// Riverpod provider for the image upload service.
final imageUploadServiceProvider = Provider<ImageUploadService>((ref) {
  return ImageUploadService(ref);
});
