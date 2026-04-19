import { Response } from 'express';
export interface PaginationMeta {
    page: number;
    limit: number;
    total: number;
    total_pages: number;
}
export declare function sendSuccess(res: Response, data: any, options?: {
    pagination?: PaginationMeta;
    status?: number;
    message?: string;
}): void;
export declare function sendMessage(res: Response, message: string, status?: number): void;
//# sourceMappingURL=response.d.ts.map