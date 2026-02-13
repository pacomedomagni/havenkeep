import { Client } from 'minio';
export declare const minioClient: Client;
export declare const BUCKET_NAME: string;
export declare function initializeBucket(): Promise<void>;
export declare function generateObjectKey(userId: string, itemId: string, filename: string): string;
export declare function getPublicUrl(objectKey: string): string;
export declare function getSignedUrl(objectKey: string, expirySeconds?: number): Promise<string>;
//# sourceMappingURL=minio.d.ts.map