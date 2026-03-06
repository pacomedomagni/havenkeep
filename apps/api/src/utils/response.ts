import { Response } from 'express';

export interface PaginationMeta {
  page: number;
  limit: number;
  total: number;
  total_pages: number;
}

export function sendSuccess(
  res: Response,
  data: any,
  options?: { pagination?: PaginationMeta; status?: number; message?: string }
): void {
  const body: Record<string, any> = { success: true, data };
  if (options?.pagination) body.pagination = options.pagination;
  if (options?.message) body.message = options.message;
  res.status(options?.status ?? 200).json(body);
}

export function sendMessage(res: Response, message: string, status: number = 200): void {
  res.status(status).json({ success: true, message });
}
