"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
const sharp_1 = __importDefault(require("sharp"));
const auth_1 = require("../middleware/auth");
const rateLimiter_1 = require("../middleware/rateLimiter");
const errorHandler_1 = require("../middleware/errorHandler");
const minio_1 = require("../config/minio");
const logger_1 = require("../utils/logger");
const db_1 = require("../db");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Configure multer for image uploads
const upload = (0, multer_1.default)({
    storage: multer_1.default.memoryStorage(),
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
        }
        else {
            cb(new Error(`File type not allowed: ${file.mimetype}`));
        }
    },
});
/**
 * @route   POST /api/v1/uploads/avatar
 * @desc    Upload a profile photo (avatar)
 * @access  Private
 */
router.post('/avatar', rateLimiter_1.uploadRateLimiter, upload.single('file'), async (req, res, next) => {
    try {
        const file = req.file;
        if (!file) {
            throw new errorHandler_1.AppError('No file uploaded', 400);
        }
        const userId = req.user.id;
        const ext = file.originalname.split('.').pop()?.toLowerCase() || 'jpg';
        const baseKey = `avatars/${userId}/avatar`;
        // Optimize and convert to WebP
        let fileBuffer;
        let contentType = 'image/webp';
        let objectKey = `${baseKey}.webp`;
        try {
            fileBuffer = await (0, sharp_1.default)(file.buffer)
                .resize(400, 400, { fit: 'cover' })
                .webp({ quality: 85 })
                .toBuffer();
        }
        catch {
            fileBuffer = file.buffer;
            contentType = file.mimetype;
            objectKey = `${baseKey}.${ext}`;
        }
        // Upload to MinIO (upsert)
        await minio_1.minioClient.putObject(minio_1.BUCKET_NAME, objectKey, fileBuffer, fileBuffer.length, {
            'Content-Type': contentType,
            'x-amz-meta-user-id': userId,
        });
        const publicUrl = (0, minio_1.getPublicUrl)(objectKey);
        logger_1.logger.info({ userId, url: publicUrl }, 'Avatar uploaded');
        res.json({
            success: true,
            data: { url: publicUrl },
        });
    }
    catch (error) {
        next(error);
    }
});
/**
 * @route   POST /api/v1/uploads/item-image
 * @desc    Upload an item product photo
 * @access  Private
 */
router.post('/item-image', rateLimiter_1.uploadRateLimiter, upload.single('file'), async (req, res, next) => {
    try {
        const file = req.file;
        if (!file) {
            throw new errorHandler_1.AppError('No file uploaded', 400);
        }
        const { itemId } = req.body;
        if (!itemId) {
            throw new errorHandler_1.AppError('itemId is required', 400);
        }
        // Verify item belongs to user
        const itemCheck = await (0, db_1.query)(`SELECT id FROM items WHERE id = $1 AND user_id = $2`, [itemId, req.user.id]);
        if (itemCheck.rows.length === 0) {
            throw new errorHandler_1.AppError('Item not found', 404);
        }
        const timestamp = Date.now();
        const baseKey = `item-images/${itemId}/${timestamp}`;
        // Optimize and convert to WebP
        let fileBuffer;
        let contentType = 'image/webp';
        let objectKey = `${baseKey}.webp`;
        try {
            fileBuffer = await (0, sharp_1.default)(file.buffer)
                .resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
                .webp({ quality: 85 })
                .toBuffer();
        }
        catch {
            fileBuffer = file.buffer;
            contentType = file.mimetype;
            const ext = file.originalname.split('.').pop()?.toLowerCase() || 'jpg';
            objectKey = `${baseKey}.${ext}`;
        }
        // Upload to MinIO
        await minio_1.minioClient.putObject(minio_1.BUCKET_NAME, objectKey, fileBuffer, fileBuffer.length, {
            'Content-Type': contentType,
            'x-amz-meta-item-id': itemId,
            'x-amz-meta-user-id': req.user.id,
        });
        const publicUrl = (0, minio_1.getPublicUrl)(objectKey);
        logger_1.logger.info({ userId: req.user.id, itemId, url: publicUrl }, 'Item image uploaded');
        res.json({
            success: true,
            data: { url: publicUrl },
        });
    }
    catch (error) {
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=uploads.js.map