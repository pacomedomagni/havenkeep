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
const errors_1 = require("../utils/errors");
const minio_1 = require("../config/minio");
const logger_1 = require("../utils/logger");
const db_1 = require("../db");
const async_handler_1 = require("../utils/async-handler");
const file_validation_1 = require("../utils/file-validation");
const response_1 = require("../utils/response");
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
router.post('/avatar', rateLimiter_1.uploadRateLimiter, upload.single('file'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const file = req.file;
    if (!file) {
        throw new errors_1.AppError('No file uploaded', 400);
    }
    if (!(0, file_validation_1.validateMagicBytes)(file.buffer, file.mimetype)) {
        throw new errors_1.AppError('File content does not match declared type', 400);
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
    (0, response_1.sendSuccess)(res, { url: publicUrl });
}));
/**
 * @route   POST /api/v1/uploads/item-image
 * @desc    Upload an item product photo
 * @access  Private
 */
router.post('/item-image', rateLimiter_1.uploadRateLimiter, upload.single('file'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const file = req.file;
    if (!file) {
        throw new errors_1.AppError('No file uploaded', 400);
    }
    if (!(0, file_validation_1.validateMagicBytes)(file.buffer, file.mimetype)) {
        throw new errors_1.AppError('File content does not match declared type', 400);
    }
    const { itemId } = req.body;
    if (!itemId) {
        throw new errors_1.AppError('itemId is required', 400);
    }
    // Verify item belongs to user
    const itemCheck = await (0, db_1.query)(`SELECT id FROM items WHERE id = $1 AND user_id = $2`, [itemId, req.user.id]);
    if (itemCheck.rows.length === 0) {
        throw new errors_1.AppError('Item not found', 404);
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
    (0, response_1.sendSuccess)(res, { url: publicUrl });
}));
exports.default = router;
//# sourceMappingURL=uploads.js.map