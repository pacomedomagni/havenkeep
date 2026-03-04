import { Router } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { query } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';
import { AppError } from '../utils/errors';
import { uploadRateLimiter } from '../middleware/rateLimiter';
import { validate } from '../middleware/validate';
import { uploadDocumentSchema, uuidParamSchema } from '../validators';
import { minioClient, BUCKET_NAME, generateObjectKey, getPublicUrl } from '../config/minio';
import { logger } from '../utils/logger';
import { AuditService } from '../services/audit.service';
import { validateMagicBytes } from '../utils/file-validation';
import { asyncHandler } from '../utils/async-handler';

// Extract MinIO object key from the full URL.
// Handles both path-style (host/<bucket>/<key>) and virtual-hosted-style (bucket.host/<key>).
function extractObjectKey(fileUrl: string, bucketName: string): string {
  const url = new URL(fileUrl);
  const pathname = url.pathname.replace(/^\//, '');
  // Path-style: remove bucket prefix if present
  if (pathname.startsWith(bucketName + '/')) {
    return pathname.slice(bucketName.length + 1);
  }
  // Virtual-hosted-style: pathname IS the key
  return pathname;
}

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
router.get('/', asyncHandler(async (req: AuthRequest, res) => {
  // Mobile sends snake_case `item_id`; accept both forms.
  const itemId = req.query.item_id ?? req.query.itemId;

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
}));

// Get single document
router.get('/:id', validate(uuidParamSchema, 'params'), asyncHandler(async (req: AuthRequest, res) => {
  const result = await query(
    `SELECT * FROM documents WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.user!.id]
  );

  if (result.rows.length === 0) {
    throw new AppError('Document not found', 404);
  }

  res.json({ document: result.rows[0] });
}));

// Upload documents
router.post(
  '/upload',
  uploadRateLimiter,
  upload.array('files', 5),
  validate(uploadDocumentSchema), // runs after multer so form fields are available; renames item_id -> itemId
  asyncHandler(async (req: AuthRequest, res) => {
    const { itemId, type } = req.body;
    const files = req.files as Express.Multer.File[];

    if (!files || files.length === 0) {
      throw new AppError('No files uploaded', 400);
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
        if (!validateMagicBytes(file.buffer, file.mimetype)) {
          throw new AppError(`File content does not match declared type: ${file.mimetype}`, 400);
        }

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
    if (uploadedDocuments.length > 0) {
      await AuditService.logFromRequest(req, 'document.upload', {
        resourceType: 'document',
        resourceId: uploadedDocuments[0].id,
        description: `Uploaded ${uploadedDocuments.length} document${uploadedDocuments.length === 1 ? '' : 's'}`,
        metadata: {
          item_id: itemId,
          count: uploadedDocuments.length,
          types: uploadedDocuments.map((doc) => doc.type),
        },
      });
    }

    res.status(201).json({
      message: uploadedDocuments.length === 1
        ? 'Document uploaded successfully'
        : 'Documents uploaded successfully',
      document: uploadedDocuments[0],
      documents: uploadedDocuments,
    });
  })
);

// Delete document
router.delete('/:id', validate(uuidParamSchema, 'params'), asyncHandler(async (req: AuthRequest, res) => {
  // Atomic ownership check + delete to prevent TOCTOU race
  const docResult = await query(
    `DELETE FROM documents WHERE id = $1 AND user_id = $2 RETURNING *`,
    [req.params.id, req.user!.id]
  );

  if (docResult.rows.length === 0) {
    throw new AppError('Document not found', 404);
  }

  const document = docResult.rows[0];

  const objectKey = extractObjectKey(document.file_url, BUCKET_NAME);

  // Delete from MinIO
  try {
    if (objectKey) {
      await minioClient.removeObject(BUCKET_NAME, objectKey);
    }

    // Delete thumbnail if exists
    if (document.thumbnail_url) {
      const thumbKey = extractObjectKey(document.thumbnail_url, BUCKET_NAME);
      if (thumbKey) {
        await minioClient.removeObject(BUCKET_NAME, thumbKey);
      }
    }
  } catch (minioError) {
    logger.warn({ error: minioError }, 'Failed to delete from MinIO');
  }

  logger.info({
    userId: req.user!.id,
    documentId: req.params.id,
  }, 'Document deleted');

  await AuditService.logFromRequest(req, 'document.delete', {
    resourceType: 'document',
    resourceId: document.id,
    description: `Deleted document: ${document.file_name || document.id}`,
    metadata: {
      item_id: document.item_id,
      mime_type: document.mime_type,
    },
  });

  res.json({ message: 'Document deleted successfully' });
}));

export default router;
