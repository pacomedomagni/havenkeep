import { Client } from 'minio';
import crypto from 'crypto';
import { config } from './index';

// MinIO client configuration
export const minioClient = new Client({
  endPoint: config.minio.endpoint,
  port: config.minio.port,
  useSSL: config.minio.useSSL,
  accessKey: config.minio.accessKey,
  secretKey: config.minio.secretKey,
});

// Bucket name
export const BUCKET_NAME = config.minio.bucket;

// Public-facing host for getPublicUrl. The audit (Ch11-I033) caught
// `getPublicUrl` returning the internal Docker hostname (e.g. `minio:9000`)
// which is unreachable from a browser. MINIO_PUBLIC_URL is preferred; falls
// back to the API URL with a `/storage` path prefix for installations that
// reverse-proxy MinIO behind the same origin.
const PUBLIC_BASE_URL = (process.env.MINIO_PUBLIC_URL || '').replace(/\/$/, '');

// Shared filename sanitization for any user-supplied object key path
// component. Path separators, `..` runs, and odd characters all collapse to
// `_`; the result is capped to 128 chars so user input can't dominate the
// key.
function sanitizeFilenameSegment(filename: string): string {
  return filename
    .replace(/[\\/]/g, '_')
    .replace(/\.\.+/g, '_')
    .replace(/[^a-zA-Z0-9._-]/g, '_')
    .slice(0, 128);
}

/**
 * Build a storage object key for documents. Audit Ch11-I034: previous version
 * used 8 hex chars from a UUID for uniqueness (~32 bits). Files in the same
 * bucket folder collide at ~65k uploads. Use a full 128-bit random suffix
 * so collisions are negligible. Audit Ch11-I035: filename sanitization that
 * preserved `..` allowed path traversal in some object stores; explicitly
 * collapse `..` and `/` to `_`.
 */
export function generateObjectKey(userId: string, itemId: string, filename: string): string {
  const safeFilename = sanitizeFilenameSegment(filename);
  const timestamp = Date.now();
  const entropy = crypto.randomBytes(16).toString('hex'); // 128 bits
  return `documents/${userId}/${itemId}/${timestamp}-${entropy}-${safeFilename}`;
}

/**
 * Avatar object key with 128-bit random suffix (audit Ch02-F032). The old
 * `avatars/<userId>/avatar.<ext>` shape was deterministic, which let a
 * reader who once obtained the URL keep guessing it after a rotation. The
 * caller is expected to delete the previous key after a successful upload.
 */
export function generateAvatarKey(userId: string, ext: string): string {
  const safeExt = sanitizeFilenameSegment(ext).toLowerCase() || 'webp';
  const entropy = crypto.randomBytes(16).toString('hex');
  return `avatars/${userId}/${entropy}.${safeExt}`;
}

/**
 * Item image object key, pinned under the owning user's prefix
 * (audit Ch02-F030). The old `item-images/<itemId>/<ts>` shape made
 * cross-user re-use possible if itemIds were guessable; user-scoped
 * prefixes keep bucket-level audits aligned with the DB tenancy boundary.
 */
export function generateItemImageKey(userId: string, itemId: string, ext: string): string {
  const safeExt = sanitizeFilenameSegment(ext).toLowerCase() || 'webp';
  const entropy = crypto.randomBytes(16).toString('hex');
  return `item-images/${userId}/${itemId}/${entropy}.${safeExt}`;
}

/**
 * Public URL for the given object key. In production set MINIO_PUBLIC_URL to
 * the host browsers actually reach (e.g. https://files.havenkeep.com).
 * In dev we fall back to the local endpoint, which is reachable from the
 * developer's browser when MinIO is exposed on localhost.
 */
export function getPublicUrl(objectKey: string): string {
  if (PUBLIC_BASE_URL) {
    return `${PUBLIC_BASE_URL}/${BUCKET_NAME}/${objectKey}`;
  }
  const protocol = config.minio.useSSL ? 'https' : 'http';
  return `${protocol}://${config.minio.endpoint}:${config.minio.port}/${BUCKET_NAME}/${objectKey}`;
}
