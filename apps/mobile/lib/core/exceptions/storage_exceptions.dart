import 'app_exceptions.dart';

/// Storage and file-related exceptions for HavenKeep app.

/// Base exception for file storage operations.
class StorageException extends AppException {
  StorageException(
    String message, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code ?? 'STORAGE_ERROR',
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage => 'Storage error occurred. Please try again.';
}

/// Exception thrown when file upload fails.
class FileUploadException extends StorageException {
  final FileUploadFailureReason reason;

  FileUploadException(
    this.reason,
    String message, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code ?? 'FILE_UPLOAD_FAILED',
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage {
    switch (reason) {
      case FileUploadFailureReason.fileTooLarge:
        return 'File is too large. Maximum size is 10MB for images, 20MB for documents.';
      case FileUploadFailureReason.invalidType:
        return 'Invalid file type. Only images (JPEG, PNG, WebP) and PDFs are allowed.';
      case FileUploadFailureReason.maliciousContent:
        return 'File appears to be corrupted or unsafe. Please try a different file.';
      case FileUploadFailureReason.networkError:
        return 'Upload failed due to network error. Please check your connection and try again.';
      case FileUploadFailureReason.serverError:
        return 'Upload failed due to server error. Please try again later.';
      case FileUploadFailureReason.insufficientStorage:
        return 'Not enough storage space. Please upgrade your plan or delete some files.';
    }
  }
}

/// Reasons why a file upload might fail.
enum FileUploadFailureReason {
  /// File exceeds maximum allowed size.
  fileTooLarge,

  /// File type is not allowed (wrong MIME type or extension).
  invalidType,

  /// File contains suspicious or malicious content.
  maliciousContent,

  /// Network error during upload.
  networkError,

  /// Server error during upload.
  serverError,

  /// User has insufficient storage quota.
  insufficientStorage,
}

/// Exception thrown when file download fails.
class FileDownloadException extends StorageException {
  FileDownloadException(
    String message, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code ?? 'FILE_DOWNLOAD_FAILED',
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage => 'Failed to download file. Please try again.';
}

/// Exception thrown when file deletion fails.
class FileDeletionException extends StorageException {
  FileDeletionException(
    String message, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code ?? 'FILE_DELETION_FAILED',
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage => 'Failed to delete file. Please try again.';
}

/// Exception thrown when storage quota is exceeded.
class StorageQuotaExceededException extends StorageException {
  final int quotaBytes;
  final int usedBytes;

  StorageQuotaExceededException({
    required this.quotaBytes,
    required this.usedBytes,
    String? code,
  }) : super(
          'Storage quota exceeded: $usedBytes/$quotaBytes bytes',
          code: code ?? 'QUOTA_EXCEEDED',
        );

  @override
  String get userMessage {
    final quotaMB = quotaBytes / (1024 * 1024);
    final usedMB = usedBytes / (1024 * 1024);
    return 'Storage full (${usedMB.toStringAsFixed(1)}/${quotaMB.toStringAsFixed(0)}MB). '
        'Please delete some files or upgrade your plan.';
  }

  @override
  bool get shouldReport => false; // Expected business logic, not an error
}

/// Exception thrown when a file is not found in storage.
class FileNotFoundException extends StorageException {
  final String filePath;

  FileNotFoundException({
    required this.filePath,
    String? code,
  }) : super(
          'File not found: $filePath',
          code: code ?? 'FILE_NOT_FOUND',
        );

  @override
  String get userMessage => 'File not found. It may have been deleted.';
}
