"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
const sharp_1 = __importDefault(require("sharp"));
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const errorHandler_1 = require("../middleware/errorHandler");
const rateLimiter_1 = require("../middleware/rateLimiter");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const minio_1 = require("../config/minio");
const logger_1 = require("../utils/logger");
const audit_service_1 = require("../services/audit.service");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Configure multer for memory storage
const upload = (0, multer_1.default)({
    storage: multer_1.default.memoryStorage(),
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
        }
        else {
            cb(new Error(`File type not allowed: ${file.mimetype}`));
        }
    },
});
// Get all documents (optionally filtered by item)
router.get('/', async (req, res, next) => {
    try {
        const { itemId } = req.query;
        if (itemId) {
            // Verify item belongs to user
            const itemCheck = await (0, db_1.query)(`SELECT id FROM items WHERE id = $1 AND user_id = $2`, [itemId, req.user.id]);
            if (itemCheck.rows.length === 0) {
                throw new errorHandler_1.AppError('Item not found', 404);
            }
            const result = await (0, db_1.query)(`SELECT * FROM documents WHERE user_id = $1 AND item_id = $2 ORDER BY created_at DESC`, [req.user.id, itemId]);
            res.json({ documents: result.rows });
        }
        else {
            // Return all documents for the user
            const result = await (0, db_1.query)(`SELECT * FROM documents WHERE user_id = $1 ORDER BY created_at DESC`, [req.user.id]);
            res.json({ documents: result.rows });
        }
    }
    catch (error) {
        next(error);
    }
});
// Get single document
router.get('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), async (req, res, next) => {
    try {
        const result = await (0, db_1.query)(`SELECT * FROM documents WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('Document not found', 404);
        }
        res.json({ document: result.rows[0] });
    }
    catch (error) {
        next(error);
    }
});
// Upload documents
router.post('/upload', rateLimiter_1.uploadRateLimiter, upload.array('files', 5), async (req, res, next) => {
    try {
        const { itemId, type } = req.body;
        const files = req.files;
        if (!files || files.length === 0) {
            throw new errorHandler_1.AppError('No files uploaded', 400);
        }
        if (!itemId) {
            throw new errorHandler_1.AppError('itemId is required', 400);
        }
        // Verify item belongs to user
        const itemCheck = await (0, db_1.query)(`SELECT id FROM items WHERE id = $1 AND user_id = $2`, [itemId, req.user.id]);
        if (itemCheck.rows.length === 0) {
            throw new errorHandler_1.AppError('Item not found', 404);
        }
        const uploadedDocuments = [];
        for (const file of files) {
            try {
                let uploadFilename = file.originalname;
                let fileBuffer = file.buffer;
                let contentType = file.mimetype;
                let thumbnailKey = null;
                // Generate thumbnail for images
                if (file.mimetype.startsWith('image/')) {
                    try {
                        // Optimize and convert to WebP
                        fileBuffer = await (0, sharp_1.default)(file.buffer)
                            .resize(2000, 2000, { fit: 'inside', withoutEnlargement: true })
                            .webp({ quality: 85 })
                            .toBuffer();
                        contentType = 'image/webp';
                        uploadFilename = file.originalname.replace(/\.[^.]+$/, '') + '.webp';
                        // Generate thumbnail
                        const thumbnailBuffer = await (0, sharp_1.default)(file.buffer)
                            .resize(300, 300, { fit: 'cover' })
                            .webp({ quality: 80 })
                            .toBuffer();
                        const objectKey = (0, minio_1.generateObjectKey)(req.user.id, itemId, uploadFilename);
                        thumbnailKey = objectKey.replace(/\.[^.]+$/, '_thumb.webp');
                        await minio_1.minioClient.putObject(minio_1.BUCKET_NAME, thumbnailKey, thumbnailBuffer, thumbnailBuffer.length, {
                            'Content-Type': 'image/webp',
                        });
                    }
                    catch (imageError) {
                        logger_1.logger.warn({ error: imageError }, 'Image optimization failed, using original');
                        fileBuffer = file.buffer;
                        contentType = file.mimetype;
                        uploadFilename = file.originalname;
                    }
                }
                const objectKey = (0, minio_1.generateObjectKey)(req.user.id, itemId, uploadFilename);
                // Upload to MinIO
                await minio_1.minioClient.putObject(minio_1.BUCKET_NAME, objectKey, fileBuffer, fileBuffer.length, {
                    'Content-Type': contentType,
                    'x-amz-meta-original-name': file.originalname,
                    'x-amz-meta-user-id': req.user.id,
                });
                const fileUrl = (0, minio_1.getPublicUrl)(objectKey);
                const thumbnailUrl = thumbnailKey ? (0, minio_1.getPublicUrl)(thumbnailKey) : null;
                // Save to database - if this fails, clean up the MinIO objects
                let docResult;
                try {
                    docResult = await (0, db_1.query)(`INSERT INTO documents (
                user_id, item_id, type, file_url, file_name, file_size, mime_type, thumbnail_url
              ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
              RETURNING *`, [
                        req.user.id,
                        itemId,
                        type || 'other',
                        fileUrl,
                        uploadFilename,
                        fileBuffer.length,
                        contentType,
                        thumbnailUrl,
                    ]);
                }
                catch (dbError) {
                    // Clean up MinIO objects on DB failure
                    logger_1.logger.warn({ objectKey, thumbnailKey }, 'DB insert failed, cleaning up MinIO objects');
                    try {
                        await minio_1.minioClient.removeObject(minio_1.BUCKET_NAME, objectKey);
                        if (thumbnailKey) {
                            await minio_1.minioClient.removeObject(minio_1.BUCKET_NAME, thumbnailKey);
                        }
                    }
                    catch (cleanupError) {
                        logger_1.logger.error({ cleanupError, objectKey }, 'Failed to clean up orphaned MinIO object');
                    }
                    throw dbError;
                }
                uploadedDocuments.push(docResult.rows[0]);
                logger_1.logger.info({
                    userId: req.user.id,
                    itemId,
                    filename: file.originalname,
                    size: fileBuffer.length,
                }, 'Document uploaded successfully');
            }
            catch (uploadError) {
                logger_1.logger.error({ error: uploadError, filename: file.originalname }, 'File upload failed');
                throw new errorHandler_1.AppError(`Failed to upload ${file.originalname}: ${uploadError.message}`, 500);
            }
        }
        // Always return consistent format with both singular and plural keys
        if (uploadedDocuments.length > 0) {
            await audit_service_1.AuditService.logFromRequest(req, 'document.upload', {
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
    }
    catch (error) {
        next(error);
    }
});
// Delete document
router.delete('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), async (req, res, next) => {
    try {
        // Get document details
        const docResult = await (0, db_1.query)(`SELECT * FROM documents WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
        if (docResult.rows.length === 0) {
            throw new errorHandler_1.AppError('Document not found', 404);
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
                await minio_1.minioClient.removeObject(minio_1.BUCKET_NAME, objectKey);
            }
            // Delete thumbnail if exists
            if (document.thumbnail_url) {
                const thumbUrl = new URL(document.thumbnail_url);
                const thumbParts = thumbUrl.pathname.replace(/^\//, '').split('/');
                thumbParts.shift(); // Remove bucket name
                const thumbKey = thumbParts.join('/');
                if (thumbKey) {
                    await minio_1.minioClient.removeObject(minio_1.BUCKET_NAME, thumbKey);
                }
            }
        }
        catch (minioError) {
            logger_1.logger.warn({ error: minioError }, 'Failed to delete from MinIO');
        }
        // Delete from database
        await (0, db_1.query)(`DELETE FROM documents WHERE id = $1`, [req.params.id]);
        logger_1.logger.info({
            userId: req.user.id,
            documentId: req.params.id,
        }, 'Document deleted');
        await audit_service_1.AuditService.logFromRequest(req, 'document.delete', {
            resourceType: 'document',
            resourceId: document.id,
            description: `Deleted document: ${document.file_name || document.id}`,
            metadata: {
                item_id: document.item_id,
                mime_type: document.mime_type,
            },
        });
        res.json({ message: 'Document deleted successfully' });
    }
    catch (error) {
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=documents.js.map