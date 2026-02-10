import { Client } from 'minio';
import { config } from './index';
import { logger } from '../utils/logger';

// MinIO client configuration
export const minioClient = new Client({
  endPoint: config.minio.endpoint,
  port: config.minio.port,
  useSSL: config.minio.useSSL,
  accessKey: config.minio.accessKey,
  secretKey: config.minio.secretKey,
});

// Bucket name
export const BUCKET_NAME = config.minio.bucket;

// Initialize bucket
export async function initializeBucket() {
  try {
    const exists = await minioClient.bucketExists(BUCKET_NAME);

    if (!exists) {
      await minioClient.makeBucket(BUCKET_NAME, 'us-east-1');
      logger.info(`✅ MinIO bucket created: ${BUCKET_NAME}`);

      // Set bucket policy for public read on specific paths
      const policy = {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Principal: { AWS: ['*'] },
            Action: ['s3:GetObject'],
            Resource: [`arn:aws:s3:::${BUCKET_NAME}/public/*`],
          },
        ],
      };

      await minioClient.setBucketPolicy(BUCKET_NAME, JSON.stringify(policy));
      logger.info('✅ MinIO bucket policy set');
    } else {
      logger.info(`✅ MinIO bucket exists: ${BUCKET_NAME}`);
    }
  } catch (error) {
    logger.error({ error }, '❌ MinIO bucket initialization failed');
    throw error;
  }
}

// Helper to generate object key
export function generateObjectKey(userId: string, itemId: string, filename: string): string {
  const timestamp = Date.now();
  const sanitizedFilename = filename.replace(/[^a-zA-Z0-9.-]/g, '_');
  return `documents/${userId}/${itemId}/${timestamp}-${sanitizedFilename}`;
}

// Helper to get public URL
export function getPublicUrl(objectKey: string): string {
  const protocol = config.minio.useSSL ? 'https' : 'http';
  return `${protocol}://${config.minio.endpoint}:${config.minio.port}/${BUCKET_NAME}/${objectKey}`;
}
