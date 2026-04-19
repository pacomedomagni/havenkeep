/**
 * Validate file content matches expected MIME type via magic bytes.
 *
 * Returns `true` when the leading bytes of `buffer` match the expected
 * signature for `mimetype`.  Unknown MIME types pass through (`true`).
 */
export declare function validateMagicBytes(buffer: Buffer, mimetype: string): boolean;
//# sourceMappingURL=file-validation.d.ts.map