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

// S-CR-02: default TTL for presigned download URLs. Short enough that a
// leaked URL (referrer header, screenshot, support inbox) is useless within
// minutes; long enough that the user's natural scroll-through-list flow
// doesn't re-fetch URLs every screen. Override per-route when a different
// trade-off is right.
export const PRESIGNED_URL_TTL_SECONDS = 15 * 60; // 15 minutes

/**
 * Mint a short-lived presigned download URL for a private object. The
 * bucket should be private (no public-read policy); each retrieval mints
 * a fresh time-bound URL on demand.
 *
 * Pre-S-CR-02 the bucket served `getPublicUrl` permanent unsigned URLs:
 * a single leaked URL gave indefinite access to the file with no
 * rotation, no revocation, no audit trail. The fix is to never persist
 * a URL — DB columns hold the object KEY only — and re-mint a presigned
 * URL on every authenticated read.
 *
 * Empty / null object key returns null (caller should treat as "no
 * file"). Caller is responsible for ownership checks BEFORE calling —
 * this helper signs whatever key it's given.
 */
export async function presignedDownloadUrl(
  objectKey: string | null | undefined,
  ttlSeconds: number = PRESIGNED_URL_TTL_SECONDS,
): Promise<string | null> {
  if (!objectKey) return null;
  return minioClient.presignedGetObject(BUCKET_NAME, objectKey, ttlSeconds);
}

/**
 * If `MINIO_PUBLIC_URL` is configured, replace the host in a presigned
 * URL produced by the MinIO SDK so browsers fetch via the public host
 * (e.g. files.havenkeep.com) rather than the internal Docker hostname
 * (e.g. minio:9000). The presigned signature stays valid because MinIO
 * signs based on path + query, not host.
 */
export function rewriteMinIOHostForBrowser(presignedUrl: string): string {
  if (!PUBLIC_BASE_URL) return presignedUrl;
  try {
    const url = new URL(presignedUrl);
    const publicUrl = new URL(PUBLIC_BASE_URL);
    url.protocol = publicUrl.protocol;
    url.host = publicUrl.host;
    return url.toString();
  } catch {
    return presignedUrl;
  }
}

/**
 * Mint a presigned URL for browser consumption. Wraps presignedDownloadUrl
 * + rewriteMinIOHostForBrowser. Returns null on null input.
 */
export async function presignedUrlForKey(
  objectKey: string | null | undefined,
  ttlSeconds: number = PRESIGNED_URL_TTL_SECONDS,
): Promise<string | null> {
  const signed = await presignedDownloadUrl(objectKey, ttlSeconds);
  if (!signed) return null;
  return rewriteMinIOHostForBrowser(signed);
}
