import { Router } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { query, getClient } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';
import { AppError } from '../utils/errors';
import { uploadRateLimiter } from '../middleware/rateLimiter';
import { idempotency } from '../middleware/idempotency';
import { validate } from '../middleware/validate';
import { uploadDocumentSchema, updateDocumentSchema, uuidParamSchema } from '../validators';
import { minioClient, BUCKET_NAME, generateObjectKey, getPublicUrl } from '../config/minio';
import { logger } from '../utils/logger';
import { AuditService } from '../services/audit.service';
import { validateMagicBytes, isMimeTypeAllowed, assertNotZipBomb } from '../utils/file-validation';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess, sendMessage } from '../utils/response';

const router = Router();
router.use(authenticate);

// Audit Ch02-F025: cap sharp's max input pixels at 100M (10kx10k) so an
// image-bomb doesn't OOM the worker. sharp's default cap is 268 megapixels
// — generous enough that a ~30MB PNG can crash a 512MB pod. Apply the cap
// once at module load.
sharp.cache(false);
sharp.concurrency(1);
const SHARP_PIXEL_LIMIT = 100_000_000;

// Audit Ch02-F026: on-disk storage means a 10MB upload doesn't pin the V8
// heap during sharp's decode. Multer cleans the temp file on response close.
// Files <= 1MB still benefit because tmpfs is page-cache backed, so the
// hit is small.
const upload = multer({
  storage: multer.diskStorage({}),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max
    files: 5, // Max 5 files per request
  },
  fileFilter: (req, file, cb) => {
    if (isMimeTypeAllowed(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`File type not allowed: ${file.mimetype}`));
    }
  },
});

// Get all documents (optionally filtered by item, paginated)
//
// Audit Ch02-F039: list endpoint enforces LIMIT/OFFSET. The previous version
// streamed every row and let the client paginate, which scaled badly once
// users had ~1k documents.
router.get('/', asyncHandler(async (req: AuthRequest, res) => {
  // Mobile sends snake_case `item_id`; accept both forms.
  const itemId = req.query.item_id ?? req.query.itemId;
  const pageNum = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
  const limitNum = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
  const offset = (pageNum - 1) * limitNum;

  if (itemId) {
    const itemCheck = await query(
      `SELECT id FROM items WHERE id = $1 AND user_id = $2`,
      [itemId, req.user!.id],
    );

    if (itemCheck.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }

    const result = await query(
      `SELECT id, item_id, user_id, type, object_key, file_name, file_size,
              mime_type, thumbnail_key, created_at, updated_at
         FROM documents
        WHERE user_id = $1 AND item_id = $2
        ORDER BY created_at DESC, id DESC
        LIMIT $3 OFFSET $4`,
      [req.user!.id, itemId, limitNum, offset],
    );

    sendSuccess(res, result.rows.map(toDocumentResponse));
    return;
  }

  const result = await query(
    `SELECT id, item_id, user_id, type, object_key, file_name, file_size,
            mime_type, thumbnail_key, created_at, updated_at
       FROM documents
      WHERE user_id = $1
      ORDER BY created_at DESC, id DESC
      LIMIT $2 OFFSET $3`,
    [req.user!.id, limitNum, offset],
  );

  sendSuccess(res, result.rows.map(toDocumentResponse));
}));

// Get single document
router.get('/:id', validate(uuidParamSchema, 'params'), asyncHandler(async (req: AuthRequest, res) => {
  const result = await query(
    `SELECT id, item_id, user_id, type, object_key, file_name, file_size,
            mime_type, thumbnail_key, created_at, updated_at
       FROM documents
      WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.user!.id],
  );

  if (result.rows.length === 0) {
    throw new AppError('Document not found', 404);
  }

  sendSuccess(res, toDocumentResponse(result.rows[0]));
}));

// Audit Ch02-F040: DB stores object_key only; URLs are built at read time
// via getPublicUrl(). This decouples the DB from the current MinIO public
// host so a hostname rotation doesn't silently break every existing link.
function toDocumentResponse(row: any): any {
  if (!row) return row;
  return {
    ...row,
    file_url: row.object_key ? getPublicUrl(row.object_key) : null,
    thumbnail_url: row.thumbnail_key ? getPublicUrl(row.thumbnail_key) : null,
  };
}

// Audit Ch02-F068: schema validation runs after multer so multipart text
// fields are populated. unknown:false (in the schema) rejects extras.
router.post(
  '/upload',
  uploadRateLimiter,
  upload.array('files', 5),
  validate(uploadDocumentSchema),
  idempotency('documents:upload'),
  asyncHandler(async (req: AuthRequest, res) => {
    const { itemId, type } = req.body;
    const files = (req.files as Express.Multer.File[]) || [];

    if (files.length === 0) {
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

    // Track every MinIO object we create so a failure mid-batch can
    // compensate by deleting each successful upload. DB inserts run in
    // a single transaction and roll back together. (Audit Ch02-F035: each
    // cleanup failure is logged separately — no swallow.)
    const uploadedDocuments: any[] = [];
    const minioObjectsToCleanup: string[] = [];
    const dbClient = await getClient();
    try {
      await dbClient.query('BEGIN');

      for (const file of files) {
        try {
          // Audit Ch02-F026: read once from disk into a buffer for the
          // magic-byte check + sharp decode. Multer disk storage gave us
          // `file.path`; we fall back to `file.buffer` when memory storage
          // is in effect (tests).
          const fs = await import('fs');
          const fileBufferRaw: Buffer = file.buffer
            ? file.buffer
            : await fs.promises.readFile(file.path);

          if (!validateMagicBytes(fileBufferRaw, file.mimetype)) {
            throw new AppError(`File content does not match declared type: ${file.mimetype}`, 400);
          }

          const bombCheck = assertNotZipBomb(fileBufferRaw, file.mimetype);
          if (!bombCheck.ok) {
            throw new AppError(`Refused upload: ${bombCheck.reason}`, 400);
          }

          let uploadFilename = file.originalname;
          let fileBuffer = fileBufferRaw;
          let contentType = file.mimetype;
          let thumbnailKey: string | null = null;

          // Generate thumbnail for images. Audit Ch02-F037: roll back the
          // entire upload if the main put fails after thumbnail upload, so
          // we don't end up with a thumbnail referencing a missing source.
          if (file.mimetype.startsWith('image/')) {
            try {
              fileBuffer = await sharp(fileBufferRaw, { limitInputPixels: SHARP_PIXEL_LIMIT })
                .resize(2000, 2000, { fit: 'inside', withoutEnlargement: true })
                .webp({ quality: 85 })
                .toBuffer();
              contentType = 'image/webp';
              uploadFilename = file.originalname.replace(/\.[^.]+$/, '') + '.webp';

              const thumbnailBuffer = await sharp(fileBufferRaw, { limitInputPixels: SHARP_PIXEL_LIMIT })
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
                },
              );
              minioObjectsToCleanup.push(thumbnailKey);
            } catch (imageError) {
              logger.warn({ error: imageError }, 'Image optimization failed, using original');
              fileBuffer = fileBufferRaw;
              contentType = file.mimetype;
              uploadFilename = file.originalname;
              thumbnailKey = null;
            }
          }

          const objectKey = generateObjectKey(req.user!.id, itemId, uploadFilename);

          await minioClient.putObject(
            BUCKET_NAME,
            objectKey,
            fileBuffer,
            fileBuffer.length,
            {
              'Content-Type': contentType,
              'x-amz-meta-original-name': file.originalname,
              'x-amz-meta-user-id': req.user!.id,
            },
          );
          minioObjectsToCleanup.push(objectKey);

          const docResult = await dbClient.query(
            `INSERT INTO documents (
              user_id, item_id, type, object_key, file_name, file_size, mime_type, thumbnail_key
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id, item_id, user_id, type, object_key, file_name, file_size, mime_type, thumbnail_key, created_at, updated_at`,
            [
              req.user!.id,
              itemId,
              type || 'other',
              objectKey,
              uploadFilename,
              fileBuffer.length,
              contentType,
              thumbnailKey,
            ],
          );

          uploadedDocuments.push(docResult.rows[0]);

          logger.info({
            userId: req.user!.id,
            itemId,
            filename: file.originalname,
            size: fileBuffer.length,
          }, 'Document uploaded successfully');
        } catch (uploadError: any) {
          logger.error({ error: uploadError, filename: file.originalname }, 'File upload failed');
          if (uploadError instanceof AppError) throw uploadError;
          throw new AppError(`Failed to upload ${file.originalname}: ${uploadError.message}`, 500);
        }
      }

      // Audit Ch02-F036: write the audit log inside the same txn as the
      // document inserts so a rollback also rolls back the audit row.
      if (uploadedDocuments.length > 0) {
        await AuditService.logFromRequestWithClient(dbClient, req, 'document.upload', {
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

      await dbClient.query('COMMIT');
    } catch (batchErr) {
      await dbClient.query('ROLLBACK').catch(() => {});
      // Audit Ch02-F035: report each cleanup failure separately so the
      // observability layer can flag persistent leaks rather than seeing
      // a single noisy log line.
      for (const key of minioObjectsToCleanup) {
        try {
          await minioClient.removeObject(BUCKET_NAME, key);
        } catch (cleanupErr) {
          logger.error({ cleanupErr, key }, 'Failed to clean up orphaned MinIO object after upload rollback');
        }
      }
      throw batchErr;
    } finally {
      dbClient.release();
    }

    const responsePayload = uploadedDocuments.length === 1
      ? toDocumentResponse(uploadedDocuments[0])
      : uploadedDocuments.map(toDocumentResponse);

    sendSuccess(res, responsePayload, {
      status: 201,
      message: uploadedDocuments.length === 1
        ? 'Document uploaded successfully'
        : 'Documents uploaded successfully',
    });
  })
);

// Update a document's metadata (rename, retag, reassign to a different item).
//
// Audit Ch08-Document-D020: previously there was no PUT route, so the
// retag/rename action in the UI was a no-op. Schema is restricted to
// non-content fields — file_url / file_size / mime_type are write-once and
// re-uploaded via POST /documents/upload.
router.put(
  '/:id',
  validate(uuidParamSchema, 'params'),
  validate(updateDocumentSchema),
  asyncHandler(async (req: AuthRequest, res) => {
    const { type, fileName, itemId } = req.body as {
      type?: string;
      fileName?: string;
      itemId?: string | null;
    };

    // If reassigning to a different item, verify the target item belongs to
    // the caller — otherwise users could move documents into other people's
    // items by guessing UUIDs.
    if (itemId !== undefined && itemId !== null) {
      const itemCheck = await query(
        `SELECT id FROM items WHERE id = $1 AND user_id = $2`,
        [itemId, req.user!.id],
      );
      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found', 404);
      }
    }

    const updates: string[] = [];
    const values: any[] = [];
    let p = 1;

    if (type !== undefined) {
      updates.push(`type = $${p++}`);
      values.push(type);
    }
    if (fileName !== undefined) {
      updates.push(`file_name = $${p++}`);
      values.push(fileName);
    }
    if (itemId !== undefined) {
      updates.push(`item_id = $${p++}`);
      values.push(itemId);
    }

    if (updates.length === 0) {
      throw new AppError('No fields to update', 400);
    }

    values.push(req.params.id, req.user!.id);

    const result = await query(
      `UPDATE documents
          SET ${updates.join(', ')},
              updated_at = NOW()
        WHERE id = $${p++} AND user_id = $${p}
        RETURNING *`,
      values,
    );

    if (result.rows.length === 0) {
      throw new AppError('Document not found', 404);
    }

    await AuditService.logFromRequest(req, 'document.upload', {
      resourceType: 'document',
      resourceId: result.rows[0].id,
      description: 'Document metadata updated',
      metadata: {
        updated_fields: Object.keys(req.body),
      },
    });

    sendSuccess(res, result.rows[0]);
  }),
);

// Delete document
//
// Audit Ch02-F038: only return success once MinIO has acknowledged the
// delete. The previous version logged the MinIO failure and 200'd the
// caller, leaving an orphan that the user thought was gone.
router.delete('/:id', validate(uuidParamSchema, 'params'), asyncHandler(async (req: AuthRequest, res) => {
  // Atomic ownership check + delete to prevent TOCTOU race
  const docResult = await query(
    `DELETE FROM documents WHERE id = $1 AND user_id = $2
     RETURNING id, item_id, user_id, type, object_key, file_name, mime_type, thumbnail_key`,
    [req.params.id, req.user!.id]
  );

  if (docResult.rows.length === 0) {
    throw new AppError('Document not found', 404);
  }

  const document = docResult.rows[0];

  // Best-effort delete of the main object + thumbnail. If either fails we
  // surface a 502 so the client can retry; the DB row is already gone, so
  // a successful retry of the same delete will 404 — clients should treat
  // 404 on retry-after-502 as success (idempotent delete).
  let mainObjectFailure: Error | null = null;
  let thumbnailFailure: Error | null = null;

  try {
    if (document.object_key) {
      await minioClient.removeObject(BUCKET_NAME, document.object_key);
    }
  } catch (err) {
    mainObjectFailure = err as Error;
  }

  try {
    if (document.thumbnail_key) {
      await minioClient.removeObject(BUCKET_NAME, document.thumbnail_key);
    }
  } catch (err) {
    thumbnailFailure = err as Error;
  }

  if (mainObjectFailure || thumbnailFailure) {
    logger.error(
      { mainObjectFailure, thumbnailFailure, documentId: document.id },
      'MinIO delete failed for one or more document objects',
    );
    throw new AppError('Failed to remove file from storage', 502);
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

  sendMessage(res, 'Document deleted successfully');
}));

export default router;
