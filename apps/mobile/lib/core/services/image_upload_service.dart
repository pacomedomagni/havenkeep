import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../utils/file_validator.dart';
import 'logging_service.dart';

/// Handles image uploads to the Express API (avatars, item photos).
///
/// All uploads are validated before being sent to prevent:
/// - Malicious files
/// - Files that are too large
/// - Wrong file types
class ImageUploadService {
  final Ref _ref;

  ImageUploadService(this._ref);

  /// Upload a profile photo for the given user.
  ///
  /// Returns the public URL of the uploaded avatar.
  Future<String> uploadProfilePhoto({
    required String userId,
    required File imageFile,
  }) async {
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

    final client = _ref.read(apiClientProvider);

    debugPrint('[ImageUpload] Uploading avatar via API');

    final data = await client.upload(
      '/api/v1/uploads/avatar',
      file: imageFile,
      fieldName: 'file',
    );

    final publicUrl = data['url'] as String;

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
  Future<String> uploadItemImage({
    required String itemId,
    required File imageFile,
  }) async {
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

    final client = _ref.read(apiClientProvider);

    debugPrint('[ImageUpload] Uploading item image via API');

    final data = await client.upload(
      '/api/v1/uploads/item-image',
      file: imageFile,
      fieldName: 'file',
      fields: {'itemId': itemId},
    );

    final publicUrl = data['url'] as String;

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
