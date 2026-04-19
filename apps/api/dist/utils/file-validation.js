"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateMagicBytes = validateMagicBytes;
/**
 * Validate file content matches expected MIME type via magic bytes.
 *
 * Returns `true` when the leading bytes of `buffer` match the expected
 * signature for `mimetype`.  Unknown MIME types pass through (`true`).
 */
function validateMagicBytes(buffer, mimetype) {
    if (buffer.length < 4)
        return false;
    const header = buffer.slice(0, 4);
    // JPEG: FF D8 FF
    if (mimetype === 'image/jpeg')
        return header[0] === 0xFF && header[1] === 0xD8 && header[2] === 0xFF;
    // PNG: 89 50 4E 47
    if (mimetype === 'image/png')
        return header[0] === 0x89 && header[1] === 0x50 && header[2] === 0x4E && header[3] === 0x47;
    // WebP: starts with RIFF....WEBP
    if (mimetype === 'image/webp')
        return buffer.length >= 12 && buffer.slice(0, 4).toString() === 'RIFF' && buffer.slice(8, 12).toString() === 'WEBP';
    // PDF: %PDF
    if (mimetype === 'application/pdf')
        return header.toString() === '%PDF';
    // HEIC/HEIF: check for ftyp box
    if (mimetype === 'image/heic' || mimetype === 'image/heif')
        return buffer.length >= 8 && buffer.slice(4, 8).toString() === 'ftyp';
    return true; // Unknown types pass through
}
//# sourceMappingURL=file-validation.js.map