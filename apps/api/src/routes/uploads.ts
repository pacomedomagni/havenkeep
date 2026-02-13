import { Router } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { authenticate, AuthRequest } from '../middleware/auth';
import { uploadRateLimiter } from '../middleware/rateLimiter';
import { AppError } from '../middleware/errorHandler';
import { minioClient, BUCKET_NAME, getPublicUrl } from '../config/minio';
import { logger } from '../utils/logger';
import { query } from '../db';

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
 */
router.post(
  '/avatar',
  uploadRateLimiter,
  upload.single('file'),
  async (req: AuthRequest, res, next) => {
    try {
      const file = req.file;
      if (!file) {
        throw new AppError('No file uploaded', 400);
      }

      const userId = req.user!.id;
      const ext = file.originalname.split('.').pop()?.toLowerCase() || 'jpg';
      const baseKey = `avatars/${userId}/avatar`;

      // Optimize and convert to WebP
      let fileBuffer: Buffer;
      let contentType = 'image/webp';
      let objectKey = `${baseKey}.webp`;
      try {
        fileBuffer = await sharp(file.buffer)
          .resize(400, 400, { fit: 'cover' })
          .webp({ quality: 85 })
          .toBuffer();
      } catch {
        fileBuffer = file.buffer;
        contentType = file.mimetype;
        objectKey = `${baseKey}.${ext}`;
      }

      // Upload to MinIO (upsert)
      await minioClient.putObject(
        BUCKET_NAME,
        objectKey,
        fileBuffer,
        fileBuffer.length,
        {
          'Content-Type': contentType,
          'x-amz-meta-user-id': userId,
        }
      );

      const publicUrl = getPublicUrl(objectKey);

      logger.info({ userId, url: publicUrl }, 'Avatar uploaded');

      res.json({
        success: true,
        data: { url: publicUrl },
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * @route   POST /api/v1/uploads/item-image
 * @desc    Upload an item product photo
 * @access  Private
 */
router.post(
  '/item-image',
  uploadRateLimiter,
  upload.single('file'),
  async (req: AuthRequest, res, next) => {
    try {
      const file = req.file;
      if (!file) {
        throw new AppError('No file uploaded', 400);
      }

      const { itemId } = req.body;
      if (!itemId) {
        throw new AppError('itemId is required', 400);
      }

      // Verify item belongs to user
      const itemCheck = await query(
        `SELECT id FROM items WHERE id = $1 AND user_id = $2`,
        [itemId, req.user!.id]
      );

      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found', 404);
      }

      const timestamp = Date.now();
      const baseKey = `item-images/${itemId}/${timestamp}`;

      // Optimize and convert to WebP
      let fileBuffer: Buffer;
      let contentType = 'image/webp';
      let objectKey = `${baseKey}.webp`;
      try {
        fileBuffer = await sharp(file.buffer)
          .resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 85 })
          .toBuffer();
      } catch {
        fileBuffer = file.buffer;
        contentType = file.mimetype;
        const ext = file.originalname.split('.').pop()?.toLowerCase() || 'jpg';
        objectKey = `${baseKey}.${ext}`;
      }

      // Upload to MinIO
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

      logger.info({ userId: req.user!.id, itemId, url: publicUrl }, 'Item image uploaded');

      res.json({
        success: true,
        data: { url: publicUrl },
      });
    } catch (error) {
      next(error);
    }
  }
);

export default router;
