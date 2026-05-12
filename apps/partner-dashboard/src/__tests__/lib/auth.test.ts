import { describe, it, expect, vi, beforeEach } from 'vitest';

// ---------------------------------------------------------------------------
// Helper: build a fake three-part JWT whose payload is the given object.
// The header and signature are dummy values — only the payload matters here.
// ---------------------------------------------------------------------------
function createFakeJwt(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = 'fakesignature';
  return `${header}.${body}.${signature}`;
}

// ---------------------------------------------------------------------------
// Mocks — must be declared before importing the module under test
// ---------------------------------------------------------------------------

// React's cache() is a server-component primitive — vitest's stubbed React
// module doesn't expose it, so we shim the simplest possible identity wrapper.
vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    cache: <T extends (...args: unknown[]) => unknown>(fn: T): T => fn,
  };
});

// Mock next/headers – cookies()
const mockCookieStore = {
  get: vi.fn(),
  set: vi.fn(),
  delete: vi.fn(),
};

vi.mock('next/headers', () => ({
  cookies: vi.fn(async () => mockCookieStore),
}));

// Mock next/navigation – redirect()
const mockRedirect = vi.fn();
vi.mock('next/navigation', () => ({
  redirect: (url: string) => {
    mockRedirect(url);
    // Next.js redirect() throws a special error to halt execution
    throw new Error(`NEXT_REDIRECT:${url}`);
  },
}));

// Mock global fetch for the getUser() API call
const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

// ---------------------------------------------------------------------------
// Now import the module under test (after mocks are in place)
// ---------------------------------------------------------------------------
import {
  isTokenExpired,
  getTokens,
  getUser,
  requireAuth,
  setAuthCookies,
  clearAuthCookies,
  ACCESS_TOKEN_COOKIE,
  REFRESH_TOKEN_COOKIE,
} from '@/lib/auth';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
});

describe('isTokenExpired', () => {
  it('returns true for a malformed token', () => {
    expect(isTokenExpired('not-a-jwt')).toBe(true);
  });

  it('returns true when the token is expired', () => {
    const expiredToken = createFakeJwt({
      userId: '1',
      email: 'a@b.com',
      exp: Math.floor(Date.now() / 1000) - 3600, // 1 hour ago
      iat: Math.floor(Date.now() / 1000) - 7200,
    });
    expect(isTokenExpired(expiredToken)).toBe(true);
  });

  it('returns false when the token is still valid', () => {
    const validToken = createFakeJwt({
      userId: '1',
      email: 'a@b.com',
      exp: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
      iat: Math.floor(Date.now() / 1000),
    });
    expect(isTokenExpired(validToken)).toBe(false);
  });
});

describe('getTokens', () => {
  it('returns null when no cookies are present', async () => {
    mockCookieStore.get.mockReturnValue(undefined);
    const tokens = await getTokens();
    expect(tokens).toBeNull();
  });

  it('returns null when only the access token is present', async () => {
    mockCookieStore.get.mockImplementation((name: string) => {
      if (name === ACCESS_TOKEN_COOKIE) return { value: 'access-tok' };
      return undefined;
    });
    const tokens = await getTokens();
    expect(tokens).toBeNull();
  });

  it('returns both tokens when cookies are set', async () => {
    mockCookieStore.get.mockImplementation((name: string) => {
      if (name === ACCESS_TOKEN_COOKIE) return { value: 'access-tok' };
      if (name === REFRESH_TOKEN_COOKIE) return { value: 'refresh-tok' };
      return undefined;
    });
    const tokens = await getTokens();
    expect(tokens).toEqual({ accessToken: 'access-tok', refreshToken: 'refresh-tok' });
  });
});

describe('getUser', () => {
  const validAccessToken = createFakeJwt({
    userId: 'u-123',
    email: 'partner@example.com',
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000),
  });

  it('returns null when there are no tokens', async () => {
    mockCookieStore.get.mockReturnValue(undefined);
    const user = await getUser();
    expect(user).toBeNull();
  });

  it('returns null when the access token payload is invalid', async () => {
    mockCookieStore.get.mockImplementation((name: string) => {
      if (name === ACCESS_TOKEN_COOKIE) return { value: 'bad.token' };
      if (name === REFRESH_TOKEN_COOKIE) return { value: 'refresh-tok' };
      return undefined;
    });
    const user = await getUser();
    expect(user).toBeNull();
  });

  it('returns user data from a valid token and successful API response', async () => {
    mockCookieStore.get.mockImplementation((name: string) => {
      if (name === ACCESS_TOKEN_COOKIE) return { value: validAccessToken };
      if (name === REFRESH_TOKEN_COOKIE) return { value: 'refresh-tok' };
      return undefined;
    });

    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        data: {
          id: 'u-123',
          email: 'partner@example.com',
          plan: 'pro',
          is_admin: false,
          is_partner: true,
        },
      }),
    });

    const user = await getUser();
    expect(user).toEqual({
      id: 'u-123',
      email: 'partner@example.com',
      plan: 'pro',
      isAdmin: false,
      isPartner: true,
    });

    // Verify the API was called with the Bearer token
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/v1/users/me'),
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: `Bearer ${validAccessToken}`,
        }),
      })
    );
  });

  it('returns null when the API responds with an error', async () => {
    mockCookieStore.get.mockImplementation((name: string) => {
      if (name === ACCESS_TOKEN_COOKIE) return { value: validAccessToken };
      if (name === REFRESH_TOKEN_COOKIE) return { value: 'refresh-tok' };
      return undefined;
    });

    mockFetch.mockResolvedValueOnce({ ok: false, status: 401 });

    const user = await getUser();
    expect(user).toBeNull();
  });

  // Audit Ch10-W047: getUser used to silently return null on a 5xx /
  // network error, which manifested as a "session expired" bounce on every
  // backend hiccup. The new contract throws ApiUnavailableError so the
  // caller can render a real error UI.
  it('throws ApiUnavailableError when fetch throws a network error', async () => {
    mockCookieStore.get.mockImplementation((name: string) => {
      if (name === ACCESS_TOKEN_COOKIE) return { value: validAccessToken };
      if (name === REFRESH_TOKEN_COOKIE) return { value: 'refresh-tok' };
      return undefined;
    });

    mockFetch.mockRejectedValueOnce(new Error('Network failure'));

    await expect(getUser()).rejects.toThrow('API unavailable');
  });
});

describe('requireAuth', () => {
  it('throws a redirect to /login when there is no user', async () => {
    mockCookieStore.get.mockReturnValue(undefined);

    await expect(requireAuth()).rejects.toThrow('NEXT_REDIRECT:/login');
    expect(mockRedirect).toHaveBeenCalledWith('/login');
  });
});

describe('setAuthCookies / clearAuthCookies', () => {
  it('sets both access and refresh cookies', () => {
    setAuthCookies('at-value', 'rt-value', mockCookieStore as any);
    expect(mockCookieStore.set).toHaveBeenCalledWith(
      ACCESS_TOKEN_COOKIE,
      'at-value',
      expect.objectContaining({ httpOnly: true, path: '/' })
    );
    expect(mockCookieStore.set).toHaveBeenCalledWith(
      REFRESH_TOKEN_COOKIE,
      'rt-value',
      expect.objectContaining({ httpOnly: true, path: '/' })
    );
  });

  it('deletes both cookies when clearing', () => {
    clearAuthCookies(mockCookieStore as any);
    expect(mockCookieStore.delete).toHaveBeenCalledWith(ACCESS_TOKEN_COOKIE);
    expect(mockCookieStore.delete).toHaveBeenCalledWith(REFRESH_TOKEN_COOKIE);
  });
});
