import { Client } from 'minio';
import crypto from 'crypto';
import { config } from './index';

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

// Helper to generate object key
export function generateObjectKey(userId: string, itemId: string, filename: string): string {
  const timestamp = Date.now();
  const sanitizedFilename = filename.replace(/[^a-zA-Z0-9.-]/g, '_');
  return `documents/${userId}/${itemId}/${timestamp}-${crypto.randomUUID().slice(0, 8)}-${sanitizedFilename}`;
}

// Helper to get public URL (for public/* paths only)
export function getPublicUrl(objectKey: string): string {
  const protocol = config.minio.useSSL ? 'https' : 'http';
  return `${protocol}://${config.minio.endpoint}:${config.minio.port}/${BUCKET_NAME}/${objectKey}`;
}