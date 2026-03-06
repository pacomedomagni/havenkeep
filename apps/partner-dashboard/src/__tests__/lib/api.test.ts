import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ---------------------------------------------------------------------------
// Mock window.location for redirect testing
// ---------------------------------------------------------------------------
const locationMock = { href: '' };
Object.defineProperty(window, 'location', { value: locationMock, writable: true });

// ---------------------------------------------------------------------------
// Mock global fetch
// ---------------------------------------------------------------------------
const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

// ---------------------------------------------------------------------------
// Import module under test (after mocks are in place)
// ---------------------------------------------------------------------------
import { apiClient, ApiError, logout } from '@/lib/api';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function makeResponse(
  status: number,
  body: unknown,
  ok?: boolean
): Response {
  const isOk = ok ?? (status >= 200 && status < 300);
  return {
    ok: isOk,
    status,
    json: async () => body,
  } as unknown as Response;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  locationMock.href = '';
});

describe('ApiError', () => {
  it('has the correct name and status', () => {
    const err = new ApiError('something went wrong', 500);
    expect(err.name).toBe('ApiError');
    expect(err.status).toBe(500);
    expect(err.message).toBe('something went wrong');
    expect(err).toBeInstanceOf(Error);
    expect(err).toBeInstanceOf(ApiError);
  });
});

describe('apiClient', () => {
  it('makes a successful GET request and returns response data', async () => {
    mockFetch.mockResolvedValueOnce(
      makeResponse(200, { success: true, data: { id: 1 } })
    );

    const result = await apiClient('/api/v1/gifts');

    expect(result).toEqual({ success: true, data: { id: 1 } });
    expect(mockFetch).toHaveBeenCalledOnce();

    const [url, opts] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(url).toContain('/api/v1/gifts');
    expect(opts.method).toBe('GET');
  });

  it('makes a successful POST request with body', async () => {
    mockFetch.mockResolvedValueOnce(
      makeResponse(201, { success: true, data: { id: 42 } })
    );

    const result = await apiClient('/api/v1/gifts', {
      method: 'POST',
      body: { name: 'Test Gift' },
    });

    expect(result).toEqual({ success: true, data: { id: 42 } });

    const [, opts] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(opts.method).toBe('POST');
    expect(opts.body).toBe(JSON.stringify({ name: 'Test Gift' }));
  });

  it('always sends credentials: include', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse(200, { success: true }));

    await apiClient('/api/v1/test');

    const [, opts] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(opts.credentials).toBe('include');
  });

  it('sets Content-Type: application/json header', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse(200, { success: true }));

    await apiClient('/api/v1/test');

    const [, opts] = mockFetch.mock.calls[0] as [string, RequestInit & { headers: Record<string, string> }];
    expect((opts.headers as Record<string, string>)['Content-Type']).toBe('application/json');
  });

  it('throws ApiError on a non-ok response with status and message from body', async () => {
    mockFetch.mockResolvedValueOnce(
      makeResponse(404, { message: 'Gift not found' }, false)
    );

    await expect(apiClient('/api/v1/gifts/999')).rejects.toMatchObject({
      name: 'ApiError',
      status: 404,
      message: 'Gift not found',
    });
  });

  it('throws ApiError with status code even when body has no message', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse(500, {}, false));

    await expect(apiClient('/api/v1/test')).rejects.toMatchObject({
      name: 'ApiError',
      status: 500,
    });
  });

  it('handles 401 by refreshing token and retrying original request', async () => {
    // First call: original request returns 401
    mockFetch.mockResolvedValueOnce(makeResponse(401, { message: 'Unauthorized' }, false));
    // Second call: refresh succeeds
    mockFetch.mockResolvedValueOnce(makeResponse(200, {}, true));
    // Third call: retry of original request succeeds
    mockFetch.mockResolvedValueOnce(makeResponse(200, { success: true, data: { id: 1 } }));

    const result = await apiClient('/api/v1/partners/analytics');

    expect(result).toEqual({ success: true, data: { id: 1 } });
    expect(mockFetch).toHaveBeenCalledTimes(3);

    // Second call should be to the refresh endpoint
    const [refreshUrl, refreshOpts] = mockFetch.mock.calls[1] as [string, RequestInit];
    expect(refreshUrl).toBe('/api/auth/refresh');
    expect(refreshOpts.method).toBe('POST');
  });

  it('redirects to /login when refresh also fails after 401', async () => {
    // First call: original request returns 401
    mockFetch.mockResolvedValueOnce(makeResponse(401, {}, false));
    // Second call: refresh also fails
    mockFetch.mockResolvedValueOnce(makeResponse(401, {}, false));

    await expect(apiClient('/api/v1/partners/analytics')).rejects.toMatchObject({
      name: 'ApiError',
      status: 401,
    });

    expect(locationMock.href).toBe('/login');
  });

  it('throws ApiError with status 408 on network timeout (AbortError)', async () => {
    const abortError = new Error('The operation was aborted');
    abortError.name = 'AbortError';
    mockFetch.mockRejectedValueOnce(abortError);

    await expect(apiClient('/api/v1/test', { timeoutMs: 1 })).rejects.toMatchObject({
      name: 'ApiError',
      status: 408,
    });
  });

  it('throws ApiError with status 0 on network error', async () => {
    mockFetch.mockRejectedValueOnce(new Error('Failed to fetch'));

    await expect(apiClient('/api/v1/test')).rejects.toMatchObject({
      name: 'ApiError',
      status: 0,
    });
  });

  it('uses base URL from NEXT_PUBLIC_API_URL when endpoint is relative', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse(200, { success: true }));

    await apiClient('/api/v1/test');

    const [url] = mockFetch.mock.calls[0] as [string, RequestInit];
    // With no env var set, API_BASE is '', so URL equals the endpoint path
    expect(url).toBe('/api/v1/test');
  });

  it('uses absolute URL as-is when endpoint starts with http', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse(200, { success: true }));

    await apiClient('https://example.com/api/data');

    const [url] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://example.com/api/data');
  });
});

describe('logout', () => {
  it('calls POST /api/auth/logout and redirects to /login', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse(200, {}));

    await logout();

    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, opts] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('/api/auth/logout');
    expect(opts.method).toBe('POST');
    expect(opts.credentials).toBe('include');
    expect(locationMock.href).toBe('/login');
  });
});
