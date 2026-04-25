import { CLIENT_FETCH_TIMEOUT_MS } from './config';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || '';

interface ApiOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  headers?: Record<string, string>;
  timeoutMs?: number;
  /**
   * Set to false to disable the single auto-refresh+retry on 401. Defaults to
   * true for everything except the refresh route itself (which would loop).
   */
  retryOnAuthFailure?: boolean;
}

/**
 * Read the double-submit CSRF cookie. The proxy enforces that this matches
 * the `X-CSRF-Token` header for any mutation (audit Ch10-W028).
 */
function getCsrfToken(): string | null {
  if (typeof document === 'undefined') return null;
  const match = document.cookie.match(/(?:^|;\s*)csrf_token=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}

const MUTATION_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

/**
 * Client-side API helper. JWT is in httpOnly cookies; mutating requests
 * must carry the double-submit CSRF token in the `X-CSRF-Token` header.
 */
export async function apiClient<T = unknown>(
  endpoint: string,
  options: ApiOptions = {}
): Promise<{ success: boolean; data?: T; message?: string; pagination?: unknown; error?: string }> {
  const {
    method = 'GET',
    body,
    headers = {},
    timeoutMs = CLIENT_FETCH_TIMEOUT_MS,
    retryOnAuthFailure = true,
  } = options;

  // Capture the body bytes once. The `Request` body is a one-shot stream, so
  // a refresh-then-retry would otherwise replay an empty body (Ch10-W049).
  const serializedBody =
    body !== undefined && method !== 'GET' ? JSON.stringify(body) : undefined;

  const csrfToken = MUTATION_METHODS.has(method) ? getCsrfToken() : null;

  function buildOptions(): RequestInit {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    const init: RequestInit = {
      method,
      credentials: 'include',
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {}),
        ...headers,
      },
    };
    if (serializedBody !== undefined) init.body = serializedBody;
    // Attach the timeout id to the controller so the caller can cancel it.
    (controller as AbortController & { __timeout?: ReturnType<typeof setTimeout> }).__timeout =
      timeout;
    return init;
  }

  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE}${endpoint}`;

  async function send(): Promise<Response> {
    const init = buildOptions();
    try {
      return await fetch(url, init);
    } finally {
      const timeout = (init.signal as unknown as { __timeout?: ReturnType<typeof setTimeout> })
        ?.__timeout;
      if (timeout) clearTimeout(timeout);
    }
  }

  let response: Response;
  try {
    response = await send();
  } catch (err: unknown) {
    if (err && typeof err === 'object' && (err as { name?: string }).name === 'AbortError') {
      throw new ApiError('Request timed out. Please try again.', 408);
    }
    throw new ApiError('Network error. Please check your connection.', 0);
  }

  if (response.status === 401 && retryOnAuthFailure) {
    // Single attempt — never retry the retry. (Ch10-W048)
    let refreshOk = false;
    try {
      const refreshController = new AbortController();
      const refreshTimeout = setTimeout(() => refreshController.abort(), timeoutMs);
      const refreshResponse = await fetch('/api/auth/refresh', {
        method: 'POST',
        credentials: 'include',
        signal: refreshController.signal,
      }).finally(() => clearTimeout(refreshTimeout));
      refreshOk = refreshResponse.ok;
    } catch {
      refreshOk = false;
    }

    if (refreshOk) {
      try {
        response = await send();
      } catch (err: unknown) {
        if (err && typeof err === 'object' && (err as { name?: string }).name === 'AbortError') {
          throw new ApiError('Request timed out. Please try again.', 408);
        }
        throw new ApiError('Network error. Please check your connection.', 0);
      }
    } else {
      if (typeof window !== 'undefined') {
        window.location.href = '/login';
      }
      throw new ApiError('Session expired. Please sign in again.', 401);
    }
  }

  if (!response.ok) {
    // 5xx surfaces as an error to callers — not absorbed as success
    // (audit Ch10-W017).
    const errorData = await response.json().catch(() => ({}));
    const message = errorData.message || errorData.error || genericMessageForStatus(response.status);
    throw new ApiError(message, response.status);
  }

  return response.json();
}

function genericMessageForStatus(status: number): string {
  if (status === 408) return 'Request timed out. Please try again.';
  if (status === 429) return 'Too many requests. Please slow down and try again.';
  if (status >= 500) return 'The service is temporarily unavailable. Please try again.';
  return `Request failed with status ${status}`;
}

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/**
 * Client-side logout — calls the server action to clear cookies and invalidate tokens.
 */
export async function logout(): Promise<void> {
  try {
    const csrfToken = getCsrfToken();
    await fetch('/api/auth/logout', {
      method: 'POST',
      credentials: 'include',
      headers: csrfToken ? { 'X-CSRF-Token': csrfToken } : undefined,
    });
  } finally {
    if (typeof window !== 'undefined') {
      window.location.href = '/login';
    }
  }
}
