import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/utils/file_validator.dart';
import 'package:havenkeep_mobile/core/exceptions/storage_exceptions.dart';

void main() {
  group('FileValidator', () {
    group('formatFileSize', () {
      test('formats bytes correctly', () {
        expect(FileValidator.formatFileSize(500), '500 B');
        expect(FileValidator.formatFileSize(1023), '1023 B');
      });

      test('formats kilobytes correctly', () {
        expect(FileValidator.formatFileSize(1024), '1.0 KB');
        expect(FileValidator.formatFileSize(1536), '1.5 KB');
        expect(FileValidator.formatFileSize(10240), '10.0 KB');
      });

      test('formats megabytes correctly', () {
        expect(FileValidator.formatFileSize(1024 * 1024), '1.0 MB');
        expect(FileValidator.formatFileSize(1536 * 1024), '1.5 MB');
        expect(FileValidator.formatFileSize(10 * 1024 * 1024), '10.0 MB');
      });
    });

    group('constants', () {
      test('max image size is 10MB', () {
        expect(FileValidator.maxImageSizeBytes, 10 * 1024 * 1024);
      });

      test('max document size is 20MB', () {
        expect(FileValidator.maxDocumentSizeBytes, 20 * 1024 * 1024);
      });

      test('allowed image types include common formats', () {
        expect(FileValidator.allowedImageTypes, contains('image/jpeg'));
        expect(FileValidator.allowedImageTypes, contains('image/png'));
        expect(FileValidator.allowedImageTypes, contains('image/webp'));
      });

      test('allowed document types include PDFs and images', () {
        expect(FileValidator.allowedDocumentTypes, contains('application/pdf'));
        expect(FileValidator.allowedDocumentTypes, contains('image/jpeg'));
        expect(FileValidator.allowedDocumentTypes, contains('image/png'));
      });
    });

    // Note: Actual file validation tests would require creating temporary test files
    // These would be tested in integration tests or with mocked file system
    group('validation behavior', () {
      test('validateImage should check file existence', () async {
        final nonExistentFile = File('/tmp/nonexistent-${DateTime.now().millisecondsSinceEpoch}.jpg');

        expect(
          () => FileValidator.validateImage(nonExistentFile),
          throwsA(isA<FileUploadException>()),
        );
      });

      test('validateDocument should check file existence', () async {
        final nonExistentFile = File('/tmp/nonexistent-${DateTime.now().millisecondsSinceEpoch}.pdf');

        expect(
          () => FileValidator.validateDocument(nonExistentFile),
          throwsA(isA<FileUploadException>()),
        );
      });
    });

    group('FileUploadFailureReason enum', () {
      test('has all expected values', () {
        expect(FileUploadFailureReason.values, hasLength(6));
        expect(FileUploadFailureReason.values, contains(FileUploadFailureReason.fileTooLarge));
        expect(FileUploadFailureReason.values, contains(FileUploadFailureReason.invalidType));
        expect(FileUploadFailureReason.values, contains(FileUploadFailureReason.maliciousContent));
        expect(FileUploadFailureReason.values, contains(FileUploadFailureReason.networkError));
        expect(FileUploadFailureReason.values, contains(FileUploadFailureReason.serverError));
        expect(FileUploadFailureReason.values, contains(FileUploadFailureReason.insufficientStorage));
      });
    });
  });
}
