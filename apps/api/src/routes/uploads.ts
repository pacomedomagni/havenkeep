import { Router } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { authenticate, AuthRequest } from '../middleware/auth';
import { uploadRateLimiter } from '../middleware/rateLimiter';
import { AppError } from '../utils/errors';
import {
  minioClient,
  BUCKET_NAME,
  getPublicUrl,
  generateAvatarKey,
  generateItemImageKey,
} from '../config/minio';
import { logger } from '../utils/logger';
import { getClient, query } from '../db';
import { asyncHandler } from '../utils/async-handler';
import { validateMagicBytes, isMimeTypeAllowed } from '../utils/file-validation';
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

    const userId = req.user!.id;

    // Optimize to WebP (preferred); fall back to original on sharp failure.
    let fileBuffer: Buffer;
    let contentType = 'image/webp';
    let ext = 'webp';
    try {
      fileBuffer = await sharp(file.buffer)
        .resize(400, 400, { fit: 'cover' })
        .webp({ quality: 85 })
        .toBuffer();
    } catch {
      fileBuffer = file.buffer;
      contentType = file.mimetype;
      ext = (file.originalname.split('.').pop() || 'jpg').toLowerCase();
    }

    const objectKey = generateAvatarKey(userId, ext);

    const dbClient = await getClient();
    let putSucceeded = false;
    try {
      await dbClient.query('BEGIN');

      // Snapshot the previous avatar object key so we can clean it up after
      // the UPDATE commits. We store the public URL in the DB; convert
      // back via URL pathname trim.
      const prevRes = await dbClient.query(
        `SELECT avatar_url FROM users WHERE id = $1 FOR UPDATE`,
        [userId],
      );
      const prevAvatarUrl: string | null = prevRes.rows[0]?.avatar_url ?? null;

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

      const publicUrl = getPublicUrl(objectKey);

      await dbClient.query(
        `UPDATE users SET avatar_url = $1, updated_at = NOW() WHERE id = $2`,
        [publicUrl, userId],
      );

      await dbClient.query('COMMIT');

      // Best-effort cleanup of the previous avatar object. Failure here is
      // logged but non-fatal — the storage GC will remove it eventually.
      if (prevAvatarUrl) {
        try {
          const prevUrl = new URL(prevAvatarUrl);
          const prevKey = prevUrl.pathname
            .replace(/^\//, '')
            .replace(new RegExp(`^${BUCKET_NAME}/`), '');
          if (prevKey && prevKey !== objectKey) {
            await minioClient.removeObject(BUCKET_NAME, prevKey);
          }
        } catch (cleanupErr) {
          logger.warn({ cleanupErr, userId }, 'Failed to clean up previous avatar');
        }
      }

      logger.info({ userId, url: publicUrl }, 'Avatar uploaded');
      sendSuccess(res, { url: publicUrl });
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

    const { itemId } = req.body;
    if (!itemId || typeof itemId !== 'string') {
      throw new AppError('itemId is required', 400);
    }

    // Verify item belongs to user + grab the previous image URL so we can
    // remove the orphan after the new put succeeds.
    const itemCheck = await query(
      `SELECT id, product_image_url FROM items WHERE id = $1 AND user_id = $2`,
      [itemId, req.user!.id]
    );

    if (itemCheck.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }
    const prevImageUrl: string | null = itemCheck.rows[0].product_image_url ?? null;

    let fileBuffer: Buffer;
    let contentType = 'image/webp';
    let ext = 'webp';
    try {
      fileBuffer = await sharp(file.buffer)
        .resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 85 })
        .toBuffer();
    } catch {
      fileBuffer = file.buffer;
      contentType = file.mimetype;
      ext = (file.originalname.split('.').pop() || 'jpg').toLowerCase();
    }

    const objectKey = generateItemImageKey(req.user!.id, itemId, ext);

    await minioClient.putObject(
      BUCKET_NAME,
      objectKey,
      fileBuffer,
      fileBuffer.length,
      {
        'Content-Type': contentType,
        'x-amz-meta-item-id': itemId,
        'x-amz-meta-user-id': req.user!.id,
      }
    );

    const publicUrl = getPublicUrl(objectKey);

    // Persist the new image URL on the item; if the persist fails, delete
    // the freshly-uploaded object so we don't orphan it.
    try {
      await query(
        `UPDATE items SET product_image_url = $1, updated_at = NOW()
         WHERE id = $2 AND user_id = $3`,
        [publicUrl, itemId, req.user!.id],
      );
    } catch (dbErr) {
      try { await minioClient.removeObject(BUCKET_NAME, objectKey); } catch (cleanupErr) {
        logger.error({ cleanupErr, key: objectKey }, 'Failed to clean up orphaned item image after DB failure');
      }
      throw dbErr;
    }

    // Best-effort: remove the previous MinIO object so it doesn't linger.
    if (prevImageUrl) {
      try {
        const prevUrl = new URL(prevImageUrl);
        const prevKey = prevUrl.pathname
          .replace(/^\//, '')
          .replace(new RegExp(`^${BUCKET_NAME}/`), '');
        if (prevKey && prevKey !== objectKey) {
          await minioClient.removeObject(BUCKET_NAME, prevKey);
        }
      } catch (cleanupErr) {
        logger.warn({ cleanupErr, itemId }, 'Failed to clean up previous item image');
      }
    }

    logger.info({ userId: req.user!.id, itemId, url: publicUrl }, 'Item image uploaded');

    sendSuccess(res, { url: publicUrl });
  })
);

export default router;
