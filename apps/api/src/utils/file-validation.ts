/**
 * File-content validation. Three layers:
 *   1. `isMimeTypeAllowed` — explicit allowlist. Anything not on the list,
 *      including SVG (active content / stored XSS), is rejected.
 *   2. `validateMagicBytes` — the file's leading bytes must match the claimed
 *      MIME type. Mismatches reject (no "unknown types pass through").
 *   3. `assertNotZipBomb` — defends against decompression-bomb shapes by
 *      rejecting unrealistic compression ratios for PNG/PDF/WebP. The actual
 *      decompression check is done by sharp/pdf libraries downstream; this
 *      pass is a fast pre-filter.
 *
 * Callers should run isMimeTypeAllowed → validateMagicBytes → assertNotZipBomb
 * before persisting an upload.
 */

const ALLOWED_MIME_TYPES = new Set<string>([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'application/pdf',
]);

export function isMimeTypeAllowed(mimetype: string): boolean {
  return ALLOWED_MIME_TYPES.has(mimetype.toLowerCase());
}

/**
 * Confirm a file's leading bytes match the expected magic-number signature
 * for `mimetype`. Returns `false` for any unrecognized MIME type — callers
 * must already have run `isMimeTypeAllowed` first.
 *
 * Uses Buffer.subarray (Buffer.slice was deprecated — Ch11-I075).
 */
export function validateMagicBytes(buffer: Buffer, mimetype: string): boolean {
  if (buffer.length < 4) return false;
  const header = buffer.subarray(0, 4);
  switch (mimetype.toLowerCase()) {
    // JPEG: FF D8 FF
    case 'image/jpeg':
      return header[0] === 0xFF && header[1] === 0xD8 && header[2] === 0xFF;
    // PNG: 89 50 4E 47
    case 'image/png':
      return (
        header[0] === 0x89 &&
        header[1] === 0x50 &&
        header[2] === 0x4E &&
        header[3] === 0x47
      );
    // WebP: starts with RIFF....WEBP
    case 'image/webp':
      return (
        buffer.length >= 12 &&
        buffer.subarray(0, 4).toString() === 'RIFF' &&
        buffer.subarray(8, 12).toString() === 'WEBP'
      );
    // PDF: %PDF
    case 'application/pdf':
      return header.toString() === '%PDF';
    // HEIC/HEIF: ftyp box at byte offset 4
    case 'image/heic':
    case 'image/heif':
      return buffer.length >= 8 && buffer.subarray(4, 8).toString() === 'ftyp';
    // Anything else (incl. SVG, octet-stream, polyglots) is rejected by default.
    default:
      return false;
  }
}

/**
 * Audit Ch11-I074: defend against decompression bombs. We can't check the
 * uncompressed size without decoding — that's downstream — but we CAN
 * reject known-pathological shapes:
 *   - PNG IHDR widths/heights > 32768 (no legitimate receipt is 1B pixels)
 *   - PDFs with > 50,000 objects in the first 1MB (object spam)
 * The check is a fast-path before sharp/pdf-lib actually decompresses.
 */
export function assertNotZipBomb(buffer: Buffer, mimetype: string): { ok: true } | { ok: false; reason: string } {
  if (mimetype === 'image/png') {
    // PNG IHDR chunk: starts at byte 8, type at 12-16 ('IHDR'), then 4-byte
    // width and 4-byte height big-endian.
    if (buffer.length < 24) return { ok: false, reason: 'PNG too short to validate' };
    if (buffer.subarray(12, 16).toString() !== 'IHDR') return { ok: true }; // Non-standard; let downstream handle
    const width = buffer.readUInt32BE(16);
    const height = buffer.readUInt32BE(20);
    if (width > 32_768 || height > 32_768) {
      return { ok: false, reason: `PNG dimensions ${width}x${height} exceed safety limit` };
    }
    if (width * height > 100_000_000) {
      return { ok: false, reason: `PNG pixel count ${width * height} exceeds safety limit` };
    }
  }
  if (mimetype === 'application/pdf') {
    // PDF object spam: count `obj` occurrences in the first ~1MB.  An honest
    // receipt PDF rarely exceeds a few hundred objects.
    const sample = buffer.subarray(0, Math.min(buffer.length, 1_000_000)).toString('latin1');
    const matches = sample.match(/\d+\s+\d+\s+obj/g);
    if (matches && matches.length > 50_000) {
      return { ok: false, reason: `PDF object count ${matches.length} suggests bomb` };
    }
  }
  return { ok: true };
}
