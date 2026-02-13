"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BUCKET_NAME = exports.minioClient = void 0;
exports.initializeBucket = initializeBucket;
exports.generateObjectKey = generateObjectKey;
exports.getPublicUrl = getPublicUrl;
exports.getSignedUrl = getSignedUrl;
const minio_1 = require("minio");
const index_1 = require("./index");
const logger_1 = require("../utils/logger");
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
// Initialize bucket
async function initializeBucket() {
    try {
        const exists = await exports.minioClient.bucketExists(exports.BUCKET_NAME);
        if (!exists) {
            await exports.minioClient.makeBucket(exports.BUCKET_NAME, 'us-east-1');
            logger_1.logger.info(`✅ MinIO bucket created: ${exports.BUCKET_NAME}`);
            // Set bucket policy for public read on specific paths
            const policy = {
                Version: '2012-10-17',
                Statement: [
                    {
                        Effect: 'Allow',
                        Principal: { AWS: ['*'] },
                        Action: ['s3:GetObject'],
                        Resource: [`arn:aws:s3:::${exports.BUCKET_NAME}/public/*`],
                    },
                ],
            };
            await exports.minioClient.setBucketPolicy(exports.BUCKET_NAME, JSON.stringify(policy));
            logger_1.logger.info('✅ MinIO bucket policy set');
        }
        else {
            logger_1.logger.info(`✅ MinIO bucket exists: ${exports.BUCKET_NAME}`);
        }
    }
    catch (error) {
        logger_1.logger.error({ error }, '❌ MinIO bucket initialization failed');
        throw error;
    }
}
// Helper to generate object key
function generateObjectKey(userId, itemId, filename) {
    const timestamp = Date.now();
    const sanitizedFilename = filename.replace(/[^a-zA-Z0-9.-]/g, '_');
    return `documents/${userId}/${itemId}/${timestamp}-${sanitizedFilename}`;
}
// Helper to get public URL (for public/* paths only)
function getPublicUrl(objectKey) {
    const protocol = index_1.config.minio.useSSL ? 'https' : 'http';
    return `${protocol}://${index_1.config.minio.endpoint}:${index_1.config.minio.port}/${exports.BUCKET_NAME}/${objectKey}`;
}
// Generate a pre-signed URL for private documents (expires in 1 hour by default)
async function getSignedUrl(objectKey, expirySeconds = 3600) {
    return exports.minioClient.presignedGetObject(exports.BUCKET_NAME, objectKey, expirySeconds);
}
//# sourceMappingURL=minio.js.map