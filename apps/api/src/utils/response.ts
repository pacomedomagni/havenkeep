import { Response } from 'express';

export interface PaginationMeta {
  page: number;
  limit: number;
  // total / total_pages are only populated for OFFSET-mode pagination — keyset
  // mode (audit Ch02-F008/F009) suppresses the count query because each page
  // does not know its global position.
  total: number | null;
  total_pages: number | null;
  // Opaque base64 cursor for the next keyset page (audit Ch02-F008/F009).
  // Null/absent on the last page or when cursor pagination is unused.
  next_cursor?: string | null;
  // Convenience flag matching `next_cursor != null`. Older callers depend
  // only on total_pages but new clients can use this directly.
  has_more?: boolean;
}

/**
 * Canonical success envelope:
 *   { success: true, data: T, meta?: { pagination?, message? } }
 *
 * Audit Ch11-I010 / I011 / I012 / I013 caught:
 *   - inconsistent shapes between sendSuccess and sendMessage
 *   - `message` placed at root collided with `data.message` for routes whose
 *     payload happens to be `{ message: ... }`
 *   - `data: any` lost type information at every callsite
 *
 * The `T` generic preserves payload typing; metadata moves under `meta` so it
 * never collides with user payload fields.
 */
export interface SuccessEnvelope<T> {
  success: true;
  data: T;
  meta?: {
    pagination?: PaginationMeta;
    message?: string;
  };
}

export function sendSuccess<T>(
  res: Response,
  data: T,
  options?: { pagination?: PaginationMeta; status?: number; message?: string },
): void {
  const body: SuccessEnvelope<T> = { success: true, data };
  if (options?.pagination || options?.message) {
    body.meta = {};
    if (options?.pagination) body.meta.pagination = options.pagination;
    if (options?.message) body.meta.message = options.message;
  }
  res.status(options?.status ?? 200).json(body);
}

/**
 * Message-only response for routes that have no payload (delete, mark-as-read,
 * etc.). The shape `{ success, message }` is intentionally distinct from the
 * payload envelope so a client can branch on the presence of `data`.
 */
export function sendMessage(res: Response, message: string, status = 200): void {
  res.status(status).json({ success: true, message });
}
