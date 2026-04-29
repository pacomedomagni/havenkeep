import { Router } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { authenticate, AuthRequest } from '../middleware/auth';
import { uploadRateLimiter } from '../middleware/rateLimiter';
import { AppError } from '../utils/errors';
import {
  minioClient,
  BUCKET_NAME,
  generateAvatarKey,
  generateItemImageKey,
  presignedUrlForKey,
} from '../config/minio';
import { logger } from '../utils/logger';
import { getClient } from '../db';
import { asyncHandler } from '../utils/async-handler';
import { validateMagicBytes, isMimeTypeAllowed, assertNotZipBomb } from '../utils/file-validation';
import { SHARP_INPUT_OPTIONS } from '../utils/sharp-config';
import { sendSuccess } from '../utils/response';

const router = Router();
router.use(authenticate);

// Configure multer for image uploads
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max
    files: 1,
  },
  fileFilter: (req, file, cb) => {
    const allowedMimes = [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif',
    ];

    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`File type not allowed: ${file.mimetype}`));
    }
  },
});

/**
 * @route   POST /api/v1/uploads/avatar
 * @desc    Upload a profile photo (avatar)
 * @access  Private
 *
 * Audit Ch02-F032/F033: avatar key uses a 128-bit random suffix instead of
 * the deterministic `avatars/<userId>/avatar.<ext>`. The DB UPDATE happens
 * in the same transaction as the MinIO put; on failure we delete the new
 * object and roll back the user row. The previous avatar is removed only
 * after the UPDATE succeeds (best-effort — orphaned objects are cleaned by
 * the storage GC sweep, audit Ch02-F031).
 */
router.post(
  '/avatar',
  uploadRateLimiter,
  upload.single('file'),
  asyncHandler(async (req: AuthRequest, res) => {
    const file = req.file;
    if (!file) {
      throw new AppError('No file uploaded', 400);
    }

    if (!isMimeTypeAllowed(file.mimetype)) {
      throw new AppError('File type not allowed', 400);
    }
    if (!validateMagicBytes(file.buffer, file.mimetype)) {
      throw new AppError('File content does not match declared type', 400);
    }
    // 1.2: reject decompression-bomb-shaped uploads BEFORE sharp tries to
    // decode. Multer caps the encoded size at 10MB but PNG zlib ratios
    // can exceed 1000:1 — a 10MB encoded PNG can decompress to ~1GB and
    // OOM the worker. assertNotZipBomb is a fast pre-filter; the
    // SHARP_INPUT_OPTIONS pixel cap below is the second line of defence.
    const bombCheck = assertNotZipBomb(file.buffer, file.mimetype);
    if (!bombCheck.ok) {
      throw new AppError(`Image rejected: ${bombCheck.reason}`, 400);
    }

    const userId = req.user!.id;

    // Optimize to WebP (preferred); fall back to original on sharp failure.
    let fileBuffer: Buffer;
    let contentType = 'image/webp';
    let ext = 'webp';
    try {
      fileBuffer = await sharp(file.buffer, SHARP_INPUT_OPTIONS)
        .resize(400, 400, { fit: 'cover' })
        .webp({ quality: 85 })
        .toBuffer();
    } catch {
      // Fall back to original bytes ONLY if sharp errored on a non-bomb
      // input (we already rejected bombs above, so the only path here
      // is "sharp doesn't recognise this format" e.g. HEIC on a build
      // without libheif). Note we deliberately do NOT fall back when
      // sharp rejects the pixel cap — failOn:'error' surfaces that as
      // a thrown error and we'd be re-uploading the bomb. Re-check the
      // size before falling through.
      if (file.buffer.length > 10 * 1024 * 1024) {
        throw new AppError('Image too large to process', 413);
      }
      fileBuffer = file.buffer;
      contentType = file.mimetype;
      ext = (file.originalname.split('.').pop() || 'jpg').toLowerCase();
    }

    const objectKey = generateAvatarKey(userId, ext);

    const dbClient = await getClient();
    let putSucceeded = false;
    try {
      await dbClient.query('BEGIN');

      // S-CR-02: column holds the object KEY, not a URL. Snapshot the
      // previous key so we can remove the orphan after the UPDATE commits.
      const prevRes = await dbClient.query(
        `SELECT avatar_url FROM users WHERE id = $1 FOR UPDATE`,
        [userId],
      );
      const prevAvatarKey: string | null = prevRes.rows[0]?.avatar_url ?? null;

      await minioClient.putObject(
        BUCKET_NAME,
        objectKey,
        fileBuffer,
        fileBuffer.length,
        {
          'Content-Type': contentType,
          'x-amz-meta-user-id': userId,
        },
      );
      putSucceeded = true;

      await dbClient.query(
        `UPDATE users SET avatar_url = $1, updated_at = NOW() WHERE id = $2`,
        [objectKey, userId],
      );

      await dbClient.query('COMMIT');

      // Best-effort cleanup of the previous avatar object. Failure here is
      // logged but non-fatal — the storage GC will remove it eventually.
      if (prevAvatarKey && prevAvatarKey !== objectKey) {
        try {
          await minioClient.removeObject(BUCKET_NAME, prevAvatarKey);
        } catch (cleanupErr) {
          logger.warn({ cleanupErr, userId }, 'Failed to clean up previous avatar');
        }
      }

      // Mint a presigned URL for the immediate response so the client
      // can render the new avatar without waiting for the next /me poll.
      const presignedUrl = await presignedUrlForKey(objectKey);
      logger.info({ userId, key: objectKey }, 'Avatar uploaded');
      sendSuccess(res, { url: presignedUrl });
    } catch (err) {
      await dbClient.query('ROLLBACK').catch(() => {});
      if (putSucceeded) {
        try {
          await minioClient.removeObject(BUCKET_NAME, objectKey);
        } catch (cleanupErr) {
          logger.error({ cleanupErr, key: objectKey }, 'Failed to clean up orphaned avatar object');
        }
      }
      throw err;
    } finally {
      dbClient.release();
    }
  }),
);

/**
 * @route   POST /api/v1/uploads/item-image
 * @desc    Upload an item product photo
 * @access  Private
 *
 * Audit Ch02-F030/F031: object key includes the owner's user_id segment
 * so cross-user access patterns line up with the DB tenancy boundary;
 * a previous item image referenced by `product_image_url` is deleted from
 * MinIO when this upload replaces it.
 */
router.post(
  '/item-image',
  uploadRateLimiter,
  upload.single('file'),
  asyncHandler(async (req: AuthRequest, res) => {
    const file = req.file;
    if (!file) {
      throw new AppError('No file uploaded', 400);
    }

    if (!isMimeTypeAllowed(file.mimetype)) {
      throw new AppError('File type not allowed', 400);
    }
    if (!validateMagicBytes(file.buffer, file.mimetype)) {
      throw new AppError('File content does not match declared type', 400);
    }
    // 1.2: zip-bomb pre-filter before sharp tries to decode.
    const bombCheck = assertNotZipBomb(file.buffer, file.mimetype);
    if (!bombCheck.ok) {
      throw new AppError(`Image rejected: ${bombCheck.reason}`, 400);
    }

    const { itemId } = req.body;
    if (!itemId || typeof itemId !== 'string') {
      throw new AppError('itemId is required', 400);
    }

    let fileBuffer: Buffer;
    let contentType = 'image/webp';
    let ext = 'webp';
    try {
      fileBuffer = await sharp(file.buffer, SHARP_INPUT_OPTIONS)
        .resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 85 })
        .toBuffer();
    } catch {
      // Fall back to original bytes ONLY for "sharp doesn't recognise"
      // failures (e.g. HEIC without libheif). Pixel-cap and bomb-shape
      // rejections were caught above. Belt-and-braces size check.
      if (file.buffer.length > 10 * 1024 * 1024) {
        throw new AppError('Image too large to process', 413);
      }
      fileBuffer = file.buffer;
      contentType = file.mimetype;
      ext = (file.originalname.split('.').pop() || 'jpg').toLowerCase();
    }

    const userId = req.user!.id;
    const objectKey = generateItemImageKey(userId, itemId, ext);

    // 2.9: row-locked transaction to close the TOCTOU window. Two
    // concurrent uploads for the same item used to both read the same
    // `prev_image_key`, both PUT to MinIO, and both UPDATE — the second
    // winner's UPDATE silently orphaned the first's MinIO object. Mirror
    // the avatar handler's BEGIN + SELECT FOR UPDATE + UPDATE + COMMIT.
    const dbClient = await getClient();
    let putSucceeded = false;
    try {
      await dbClient.query('BEGIN');

      const prevRes = await dbClient.query(
        `SELECT product_image_url FROM items WHERE id = $1 AND user_id = $2 FOR UPDATE`,
        [itemId, userId],
      );

      if (prevRes.rows.length === 0) {
        await dbClient.query('ROLLBACK');
        throw new AppError('Item not found', 404);
      }

      const prevImageKey: string | null = prevRes.rows[0].product_image_url ?? null;

      await minioClient.putObject(
        BUCKET_NAME,
        objectKey,
        fileBuffer,
        fileBuffer.length,
        {
          'Content-Type': contentType,
          'x-amz-meta-item-id': itemId,
          'x-amz-meta-user-id': userId,
        },
      );
      putSucceeded = true;

      await dbClient.query(
        `UPDATE items SET product_image_url = $1, updated_at = NOW()
          WHERE id = $2 AND user_id = $3`,
        [objectKey, itemId, userId],
      );

      await dbClient.query('COMMIT');

      // Best-effort cleanup of the previous MinIO object. Failure here is
      // logged but non-fatal.
      if (prevImageKey && prevImageKey !== objectKey) {
        try {
          await minioClient.removeObject(BUCKET_NAME, prevImageKey);
        } catch (cleanupErr) {
          logger.warn({ cleanupErr, itemId }, 'Failed to clean up previous item image');
        }
      }

      const presignedUrl = await presignedUrlForKey(objectKey);
      logger.info({ userId, itemId, key: objectKey }, 'Item image uploaded');
      sendSuccess(res, { url: presignedUrl });
    } catch (err) {
      await dbClient.query('ROLLBACK').catch(() => {});
      if (putSucceeded) {
        try {
          await minioClient.removeObject(BUCKET_NAME, objectKey);
        } catch (cleanupErr) {
          logger.error(
            { cleanupErr, key: objectKey },
            'Failed to clean up orphaned item image after DB failure',
          );
        }
      }
      throw err;
    } finally {
      dbClient.release();
    }
  }),
);

export default router;
