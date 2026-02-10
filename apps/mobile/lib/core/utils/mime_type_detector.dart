import 'dart:io';

/// MIME type detection utilities using magic numbers (file signatures).
///
/// Detects actual file type by reading the first few bytes of the file,
/// regardless of the file extension. This prevents malicious files disguised
/// with incorrect extensions.
class MimeTypeDetector {
  /// Detects MIME type by reading file signature (magic numbers).
  ///
  /// Returns the detected MIME type or null if unable to determine.
  static Future<String?> detect(File file) async {
    if (!await file.exists()) {
      return null;
    }

    try {
      // Read first 12 bytes for magic number detection
      final bytes = await file.openRead(0, 12).expand((x) => x).toList();

      if (bytes.isEmpty) {
        return null;
      }

      // Check JPEG
      if (bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF) {
        return 'image/jpeg';
      }

      // Check PNG
      if (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A) {
        return 'image/png';
      }

      // Check WebP
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }

      // Check PDF
      if (bytes.length >= 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46) {
        return 'application/pdf';
      }

      // Check GIF
      if (bytes.length >= 6 &&
          bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38 &&
          (bytes[4] == 0x37 || bytes[4] == 0x39) &&
          bytes[5] == 0x61) {
        return 'image/gif';
      }

      // Check BMP
      if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
        return 'image/bmp';
      }

      // Check ZIP (used by some office formats)
      if (bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
          (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08)) {
        return 'application/zip';
      }

      // Unknown type
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Checks if file signature matches the expected MIME type.
  ///
  /// Returns true if the file content matches the claimed MIME type.
  static Future<bool> verify(File file, String expectedMimeType) async {
    final detectedType = await detect(file);
    if (detectedType == null) {
      return false;
    }
    return detectedType == expectedMimeType;
  }
}
