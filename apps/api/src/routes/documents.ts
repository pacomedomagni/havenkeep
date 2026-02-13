import { Router } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { query } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { uploadRateLimiter } from '../middleware/rateLimiter';
import { validate } from '../middleware/validate';
import { uploadDocumentSchema, uuidParamSchema } from '../validators';
import { minioClient, BUCKET_NAME, generateObjectKey, getPublicUrl } from '../config/minio';
import { logger } from '../utils/logger';

const router = Router();
router.use(authenticate);

// Configure multer for memory storage
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max
    files: 5, // Max 5 files per request
  },
  fileFilter: (req, file, cb) => {
    // Allowed file types
    const allowedMimes = [
      'image/jpeg',
      'image/png',
      'image/webp',
      'application/pdf',
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

// Get all documents (optionally filtered by item)
router.get('/', async (req: AuthRequest, res, next) => {
  try {
    const { itemId } = req.query;

    if (itemId) {
      // Verify item belongs to user
      const itemCheck = await query(
        `SELECT id FROM items WHERE id = $1 AND user_id = $2`,
        [itemId, req.user!.id]
      );

      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found', 404);
      }

      const result = await query(
        `SELECT * FROM documents WHERE user_id = $1 AND item_id = $2 ORDER BY created_at DESC`,
        [req.user!.id, itemId]
      );

      res.json({ documents: result.rows });
    } else {
      // Return all documents for the user
      const result = await query(
        `SELECT * FROM documents WHERE user_id = $1 ORDER BY created_at DESC`,
        [req.user!.id]
      );

      res.json({ documents: result.rows });
    }
  } catch (error) {
    next(error);
  }
});

// Get single document
router.get('/:id', validate(uuidParamSchema, 'params'), async (req: AuthRequest, res, next) => {
  try {
    const result = await query(
      `SELECT * FROM documents WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError('Document not found', 404);
    }

    res.json({ document: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Upload documents
router.post(
  '/upload',
  uploadRateLimiter,
  upload.array('files', 5),
  async (req: AuthRequest, res, next) => {
    try {
      const { itemId, type } = req.body;
      const files = req.files as Express.Multer.File[];

      if (!files || files.length === 0) {
        throw new AppError('No files uploaded', 400);
      }

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

      const uploadedDocuments = [];

      for (const file of files) {
        try {
          let uploadFilename = file.originalname;
          let fileBuffer = file.buffer;
          let contentType = file.mimetype;
          let thumbnailKey: string | null = null;

          // Generate thumbnail for images
          if (file.mimetype.startsWith('image/')) {
            try {
              // Optimize and convert to WebP
              fileBuffer = await sharp(file.buffer)
                .resize(2000, 2000, { fit: 'inside', withoutEnlargement: true })
                .webp({ quality: 85 })
                .toBuffer();
              contentType = 'image/webp';
              uploadFilename = file.originalname.replace(/\.[^.]+$/, '') + '.webp';

              // Generate thumbnail
              const thumbnailBuffer = await sharp(file.buffer)
                .resize(300, 300, { fit: 'cover' })
                .webp({ quality: 80 })
                .toBuffer();

              const objectKey = generateObjectKey(req.user!.id, itemId, uploadFilename);
              thumbnailKey = objectKey.replace(/\.[^.]+$/, '_thumb.webp');

              await minioClient.putObject(
                BUCKET_NAME,
                thumbnailKey,
                thumbnailBuffer,
                thumbnailBuffer.length,
                {
                  'Content-Type': 'image/webp',
                }
              );
            } catch (imageError) {
              logger.warn({ error: imageError }, 'Image optimization failed, using original');
              fileBuffer = file.buffer;
              contentType = file.mimetype;
              uploadFilename = file.originalname;
            }
          }

          const objectKey = generateObjectKey(req.user!.id, itemId, uploadFilename);

          // Upload to MinIO
          await minioClient.putObject(
            BUCKET_NAME,
            objectKey,
            fileBuffer,
            fileBuffer.length,
            {
              'Content-Type': contentType,
              'x-amz-meta-original-name': file.originalname,
              'x-amz-meta-user-id': req.user!.id,
            }
          );

          const fileUrl = getPublicUrl(objectKey);
          const thumbnailUrl = thumbnailKey ? getPublicUrl(thumbnailKey) : null;

          // Save to database - if this fails, clean up the MinIO objects
          let docResult;
          try {
            docResult = await query(
              `INSERT INTO documents (
                user_id, item_id, type, file_url, file_name, file_size, mime_type, thumbnail_url
              ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
              RETURNING *`,
              [
                req.user!.id,
                itemId,
                type || 'other',
                fileUrl,
                uploadFilename,
                fileBuffer.length,
                contentType,
                thumbnailUrl,
              ]
            );
          } catch (dbError) {
            // Clean up MinIO objects on DB failure
            logger.warn({ objectKey, thumbnailKey }, 'DB insert failed, cleaning up MinIO objects');
            try {
              await minioClient.removeObject(BUCKET_NAME, objectKey);
              if (thumbnailKey) {
                await minioClient.removeObject(BUCKET_NAME, thumbnailKey);
              }
            } catch (cleanupError) {
              logger.error({ cleanupError, objectKey }, 'Failed to clean up orphaned MinIO object');
            }
            throw dbError;
          }

          uploadedDocuments.push(docResult.rows[0]);

          logger.info({
            userId: req.user!.id,
            itemId,
            filename: file.originalname,
            size: fileBuffer.length,
          }, 'Document uploaded successfully');
        } catch (uploadError: any) {
          logger.error({ error: uploadError, filename: file.originalname }, 'File upload failed');
          throw new AppError(`Failed to upload ${file.originalname}: ${uploadError.message}`, 500);
        }
      }

      // Always return consistent format with both singular and plural keys
      res.status(201).json({
        message: uploadedDocuments.length === 1
          ? 'Document uploaded successfully'
          : 'Documents uploaded successfully',
        document: uploadedDocuments[0],
        documents: uploadedDocuments,
      });
    } catch (error) {
      next(error);
    }
  }
);

// Delete document
router.delete('/:id', validate(uuidParamSchema, 'params'), async (req: AuthRequest, res, next) => {
  try {
    // Get document details
    const docResult = await query(
      `SELECT * FROM documents WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (docResult.rows.length === 0) {
      throw new AppError('Document not found', 404);
    }

    const document = docResult.rows[0];

    // Extract object key from URL — pathname is /<bucket>/<key>, strip bucket prefix
    const url = new URL(document.file_url);
    const pathParts = url.pathname.replace(/^\//, '').split('/');
    pathParts.shift(); // Remove bucket name
    const objectKey = pathParts.join('/');

    // Delete from MinIO
    try {
      if (objectKey) {
        await minioClient.removeObject(BUCKET_NAME, objectKey);
      }

      // Delete thumbnail if exists
      if (document.thumbnail_url) {
        const thumbUrl = new URL(document.thumbnail_url);
        const thumbParts = thumbUrl.pathname.replace(/^\//, '').split('/');
        thumbParts.shift(); // Remove bucket name
        const thumbKey = thumbParts.join('/');
        if (thumbKey) {
          await minioClient.removeObject(BUCKET_NAME, thumbKey);
        }
      }
    } catch (minioError) {
      logger.warn({ error: minioError }, 'Failed to delete from MinIO');
    }

    // Delete from database
    await query(`DELETE FROM documents WHERE id = $1`, [req.params.id]);

    logger.info({
      userId: req.user!.id,
      documentId: req.params.id,
    }, 'Document deleted');

    res.json({ message: 'Document deleted successfully' });
  } catch (error) {
    next(error);
  }
});

export default router;
