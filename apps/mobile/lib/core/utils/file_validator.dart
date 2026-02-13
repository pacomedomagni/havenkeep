import 'dart:io';

import '../exceptions/storage_exceptions.dart';
import 'mime_type_detector.dart';

/// File validation utilities for HavenKeep.
///
/// Validates file uploads to prevent:
/// - Files that are too large
/// - Wrong file types (MIME type mismatch)
/// - Malicious files disguised with wrong extensions
/// - Executable content
class FileValidator {
  // Maximum file sizes (in bytes)
  static const int maxImageSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int maxDocumentSizeBytes = 10 * 1024 * 1024; // 10MB

  // Allowed MIME types
  static const List<String> allowedImageTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  ];

  static const List<String> allowedDocumentTypes = [
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  ];

  /// Validates an image file before upload.
  ///
  /// Checks:
  /// - File exists
  /// - File size within limits
  /// - MIME type is allowed
  /// - File content matches claimed type (magic numbers)
  /// - No executable content
  ///
  /// Throws [FileUploadException] if validation fails.
  static Future<void> validateImage(File file) async {
    // 1. Check file exists
    if (!await file.exists()) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'File does not exist',
      );
    }

    // 2. Check file size
    final size = await file.length();
    if (size == 0) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'File is empty',
      );
    }

    if (size > maxImageSizeBytes) {
      throw FileUploadException(
        FileUploadFailureReason.fileTooLarge,
        'File size: ${size}B exceeds max: ${maxImageSizeBytes}B (${(maxImageSizeBytes / (1024 * 1024)).toStringAsFixed(0)}MB)',
      );
    }

    // 3. Detect actual MIME type from file content
    final detectedType = await MimeTypeDetector.detect(file);
    if (detectedType == null) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'Unable to determine file type',
      );
    }

    // 4. Check if detected type is allowed
    if (!allowedImageTypes.contains(detectedType)) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'Detected type "$detectedType" is not allowed. Allowed types: ${allowedImageTypes.join(', ')}',
      );
    }

    // 5. Check for suspicious content
    if (await _containsSuspiciousContent(file)) {
      throw FileUploadException(
        FileUploadFailureReason.maliciousContent,
        'File contains suspicious content',
      );
    }
  }

  /// Validates a document file (PDF or image) before upload.
  ///
  /// Similar to [validateImage] but with larger size limit and accepts PDFs.
  static Future<void> validateDocument(File file) async {
    // 1. Check file exists
    if (!await file.exists()) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'File does not exist',
      );
    }

    // 2. Check file size
    final size = await file.length();
    if (size == 0) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'File is empty',
      );
    }

    if (size > maxDocumentSizeBytes) {
      throw FileUploadException(
        FileUploadFailureReason.fileTooLarge,
        'File size: ${size}B exceeds max: ${maxDocumentSizeBytes}B (${(maxDocumentSizeBytes / (1024 * 1024)).toStringAsFixed(0)}MB)',
      );
    }

    // 3. Detect actual MIME type
    final detectedType = await MimeTypeDetector.detect(file);
    if (detectedType == null) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'Unable to determine file type',
      );
    }

    // 4. Check if type is allowed
    if (!allowedDocumentTypes.contains(detectedType)) {
      throw FileUploadException(
        FileUploadFailureReason.invalidType,
        'Detected type "$detectedType" is not allowed. Allowed types: ${allowedDocumentTypes.join(', ')}',
      );
    }

    // 5. Check for suspicious content
    if (await _containsSuspiciousContent(file)) {
      throw FileUploadException(
        FileUploadFailureReason.maliciousContent,
        'File contains suspicious content',
      );
    }
  }

  /// Checks if file contains suspicious patterns that could indicate malicious content.
  ///
  /// Scans for:
  /// - Executable signatures (PE, ELF, Mach-O)
  /// - Script tags (HTML/JavaScript)
  /// - PHP code markers
  static Future<bool> _containsSuspiciousContent(File file) async {
    try {
      // Read first 1KB for pattern matching
      final bytes = await file.openRead(0, 1024).expand((x) => x).toList();

      // Check for PE executable signature (Windows .exe, .dll)
      if (bytes.length >= 2 && bytes[0] == 0x4D && bytes[1] == 0x5A) {
        return true; // "MZ" header
      }

      // Check for ELF executable signature (Linux)
      if (bytes.length >= 4 &&
          bytes[0] == 0x7F &&
          bytes[1] == 0x45 &&
          bytes[2] == 0x4C &&
          bytes[3] == 0x46) {
        return true; // "\x7FELF" header
      }

      // Check for Mach-O executable signature (macOS)
      if (bytes.length >= 4) {
        final magic = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
        if (magic == 0xFEEDFACE ||
            magic == 0xFEEDFACF ||
            magic == 0xCEFAEDFE ||
            magic == 0xCFFAEDFE) {
          return true;
        }
      }

      // Convert to string for text-based pattern matching
      final content = String.fromCharCodes(bytes);

      // Check for script tags and suspicious patterns
      final dangerousPatterns = [
        RegExp(r'<script', caseSensitive: false),
        RegExp(r'javascript:', caseSensitive: false),
        RegExp(r'<\?php', caseSensitive: false),
        RegExp(r'eval\s*\(', caseSensitive: false),
        RegExp(r'exec\s*\(', caseSensitive: false),
      ];

      for (final pattern in dangerousPatterns) {
        if (pattern.hasMatch(content)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      // If we can't read the file, consider it suspicious
      return true;
    }
  }

  /// Get human-readable file size string.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
