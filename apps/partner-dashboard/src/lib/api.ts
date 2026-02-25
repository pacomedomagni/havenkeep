const API_BASE = process.env.NEXT_PUBLIC_API_URL || '';
const API_TIMEOUT_MS = 30_000; // 30 seconds

interface ApiOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: any;
  headers?: Record<string, string>;
  timeoutMs?: number;
}

/**
 * Client-side API helper. JWT is stored in httpOnly cookies,
 * so credentials are included automatically on same-origin requests
 * that go through the Next.js rewrite proxy (/api/v1/*).
 */
export async function apiClient<T = any>(
  endpoint: string,
  options: ApiOptions = {}
): Promise<{ success: boolean; data?: T; message?: string; pagination?: any; error?: string }> {
  const { method = 'GET', body, headers = {}, timeoutMs = API_TIMEOUT_MS } = options;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  const fetchOptions: RequestInit = {
    method,
    credentials: 'include',
    signal: controller.signal,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
  };

  if (body && method !== 'GET') {
    fetchOptions.body = JSON.stringify(body);
  }

  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE}${endpoint}`;

  let response: Response;
  try {
    response = await fetch(url, fetchOptions);
  } catch (err: any) {
    clearTimeout(timeout);
    if (err.name === 'AbortError') {
      throw new ApiError('Request timed out. Please try again.', 408);
    }
    throw new ApiError('Network error. Please check your connection.', 0);
  }
  clearTimeout(timeout);

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new ApiError(
      errorData.message || errorData.error || `Request failed with status ${response.status}`,
      response.status
    );
  }

  return response.json();
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
  await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });
  window.location.href = '/login';
}
