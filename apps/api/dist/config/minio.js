"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.BUCKET_NAME = exports.minioClient = void 0;
exports.generateObjectKey = generateObjectKey;
exports.getPublicUrl = getPublicUrl;
const minio_1 = require("minio");
const crypto_1 = __importDefault(require("crypto"));
const index_1 = require("./index");
// MinIO client configuration
exports.minioClient = new minio_1.Client({
    endPoint: index_1.config.minio.endpoint,
    port: index_1.config.minio.port,
    useSSL: index_1.config.minio.useSSL,
    accessKey: index_1.config.minio.accessKey,
    secretKey: index_1.config.minio.secretKey,
});
// Bucket name
exports.BUCKET_NAME = index_1.config.minio.bucket;
// Helper to generate object key
function generateObjectKey(userId, itemId, filename) {
    const timestamp = Date.now();
    const sanitizedFilename = filename.replace(/[^a-zA-Z0-9.-]/g, '_');
    return `documents/${userId}/${itemId}/${timestamp}-${crypto_1.default.randomUUID().slice(0, 8)}-${sanitizedFilename}`;
}
// Helper to get public URL (for public/* paths only)
function getPublicUrl(objectKey) {
    const protocol = index_1.config.minio.useSSL ? 'https' : 'http';
    return `${protocol}://${index_1.config.minio.endpoint}:${index_1.config.minio.port}/${exports.BUCKET_NAME}/${objectKey}`;
}
//# sourceMappingURL=minio.js.map