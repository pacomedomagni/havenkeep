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
 *
 * Parses the cookie header by splitting on `; ` and matching the exact name
 * `csrf_token` — earlier shape used a single regex match that would match
 * `csrf_token_old=...` if anyone set a cookie with that prefix. Defense in
 * depth; the proxy still requires header + cookie to agree.
 */
function getCsrfToken(): string | null {
  if (typeof document === 'undefined') return null;
  const cookies = document.cookie.split('; ');
  for (const c of cookies) {
    const eq = c.indexOf('=');
    if (eq === -1) continue;
    if (c.slice(0, eq) === 'csrf_token') {
      try {
        return decodeURIComponent(c.slice(eq + 1));
      } catch {
        return null;
      }
    }
  }
  return null;
}

const MUTATION_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

// S2-S: a burst of 401s shouldn't fan out into a stampede of /auth/refresh
// calls — each one rotates the refresh family on the server, so the second
// concurrent caller would invalidate the first's freshly-minted access
// token. Funnel everyone through a single shared promise; the first 401
// kicks off the refresh, the rest await the same result.
let inFlightRefresh: Promise<boolean> | null = null;

function refreshOnce(timeoutMs: number): Promise<boolean> {
  if (inFlightRefresh) return inFlightRefresh;
  const refreshController = new AbortController();
  const refreshTimeout = setTimeout(() => refreshController.abort(), timeoutMs);
  inFlightRefresh = (async () => {
    try {
      const refreshResponse = await fetch('/api/auth/refresh', {
        method: 'POST',
        credentials: 'include',
        signal: refreshController.signal,
      });
      return refreshResponse.ok;
    } catch {
      return false;
    } finally {
      clearTimeout(refreshTimeout);
      // Clear the slot so the *next* 401 (after this one resolves)
      // can start a new refresh — we don't want to cache a permanent
      // failure or success across the session.
      inFlightRefresh = null;
    }
  })();
  return inFlightRefresh;
}

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
    // Single-flight refresh per S2-S: concurrent 401s share one /auth/refresh.
    const refreshOk = await refreshOnce(timeoutMs);

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
