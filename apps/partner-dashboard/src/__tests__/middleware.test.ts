import { describe, it, expect, vi, beforeEach } from 'vitest';

// ---------------------------------------------------------------------------
// Helper: build a fake three-part JWT whose payload is the given object.
// ---------------------------------------------------------------------------
function createFakeJwt(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = 'fakesignature';
  return `${header}.${body}.${signature}`;
}

// ---------------------------------------------------------------------------
// A cookie jar used by both fake request and fake response objects.
// ---------------------------------------------------------------------------
class FakeCookies {
  private jar = new Map<string, { name: string; value: string }>();

  set(name: string, value: string, _options?: Record<string, unknown>) {
    this.jar.set(name, { name, value });
  }

  get(name: string) {
    return this.jar.get(name);
  }

  delete(name: string) {
    this.jar.delete(name);
  }

  getAll() {
    return [...this.jar.values()];
  }
}

// ---------------------------------------------------------------------------
// vi.hoisted() — values declared here are available to hoisted vi.mock calls.
// ---------------------------------------------------------------------------
const { FakeNextResponse } = vi.hoisted(() => {
  // Minimal FakeCookies clone for use inside the hoisted scope
  class HoistedFakeCookies {
    private jar = new Map<string, { name: string; value: string }>();
    set(name: string, value: string, _options?: Record<string, unknown>) {
      this.jar.set(name, { name, value });
    }
    get(name: string) {
      return this.jar.get(name);
    }
    delete(name: string) {
      this.jar.delete(name);
    }
  }

  const FakeNextResponse = {
    redirect(url: URL | string) {
      const target = typeof url === 'string' ? url : url.toString();
      const cookies = new HoistedFakeCookies();
      return { type: 'redirect' as const, url: target, cookies };
    },
    next() {
      const cookies = new HoistedFakeCookies();
      return { type: 'next' as const, cookies };
    },
  };

  return { FakeNextResponse };
});

vi.mock('next/server', () => ({
  NextResponse: FakeNextResponse,
}));

// Mock global fetch (used by the token-refresh flow inside middleware)
const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

// ---------------------------------------------------------------------------
// Import the middleware after mocks are installed.
// File lives at apps/partner-dashboard/src/middleware.ts — the only path
// Next 14 looks at when the project uses src/app.
// ---------------------------------------------------------------------------
import { middleware } from '../middleware';

// ---------------------------------------------------------------------------
// Constants (must match those in middleware.ts)
// ---------------------------------------------------------------------------
const ACCESS_TOKEN_COOKIE = 'hk_access_token';
const REFRESH_TOKEN_COOKIE = 'hk_refresh_token';

// ---------------------------------------------------------------------------
// Helper to build a fake NextRequest-like object
// ---------------------------------------------------------------------------
function createNextRequest(
  url: string,
  cookieEntries: Record<string, string> = {}
) {
  const parsedUrl = new URL(url);
  const cookies = new FakeCookies();
  for (const [k, v] of Object.entries(cookieEntries)) {
    cookies.set(k, v);
  }

  return {
    url,
    nextUrl: parsedUrl,
    cookies,
    headers: new Headers(),
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
beforeEach(() => {
  vi.clearAllMocks();
  mockFetch.mockReset();
});

describe('middleware', () => {
  // -----------------------------------------------------------------------
  // Unauthenticated requests
  // -----------------------------------------------------------------------
  describe('unauthenticated requests', () => {
    it('redirects to /login when accessing /dashboard without tokens', async () => {
      const req = createNextRequest('http://localhost:3001/dashboard');
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/login');
    });

    it('redirects to /login when accessing /admin without tokens', async () => {
      const req = createNextRequest('http://localhost:3001/admin');
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/login');
    });

    it('allows unauthenticated access to /login', async () => {
      const req = createNextRequest('http://localhost:3001/login');
      const res = await middleware(req as any);
      expect(res.type).toBe('next');
    });

    it('allows unauthenticated access to /signup', async () => {
      const req = createNextRequest('http://localhost:3001/signup');
      const res = await middleware(req as any);
      expect(res.type).toBe('next');
    });
  });

  // -----------------------------------------------------------------------
  // Authenticated requests -- valid partner token
  // -----------------------------------------------------------------------
  describe('authenticated partner requests', () => {
    const partnerToken = createFakeJwt({
      userId: 'p-1',
      email: 'partner@test.com',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000),
      isPartner: true,
    });

    // H-A8: middleware no longer trusts the unverified JWT for role gating —
    // it asks the API every ~30 seconds. Each test in this block must mock
    // the `/auth/role-check` response so the middleware can derive isPartner.
    beforeEach(() => {
      mockFetch.mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({ data: { is_admin: false, is_partner: true } }),
      });
    });

    it('passes through to /dashboard for a partner', async () => {
      const req = createNextRequest('http://localhost:3001/dashboard', {
        [ACCESS_TOKEN_COOKIE]: partnerToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('next');
    });

    it('redirects partner from /login to /dashboard', async () => {
      const req = createNextRequest('http://localhost:3001/login', {
        [ACCESS_TOKEN_COOKIE]: partnerToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/dashboard');
    });

    it('redirects partner away from /admin to /unauthorized', async () => {
      const req = createNextRequest('http://localhost:3001/admin', {
        [ACCESS_TOKEN_COOKIE]: partnerToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/unauthorized');
    });
  });

  // -----------------------------------------------------------------------
  // Authenticated requests -- valid admin token
  // -----------------------------------------------------------------------
  describe('authenticated admin requests', () => {
    const adminToken = createFakeJwt({
      userId: 'a-1',
      email: 'admin@test.com',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000),
      isAdmin: true,
    });

    beforeEach(() => {
      mockFetch.mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({ data: { is_admin: true, is_partner: false } }),
      });
    });

    it('passes through to /admin for an admin', async () => {
      const req = createNextRequest('http://localhost:3001/admin', {
        [ACCESS_TOKEN_COOKIE]: adminToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('next');
    });

    it('redirects admin from /login to /admin', async () => {
      const req = createNextRequest('http://localhost:3001/login', {
        [ACCESS_TOKEN_COOKIE]: adminToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/admin');
    });
  });

  // -----------------------------------------------------------------------
  // Root route
  // -----------------------------------------------------------------------
  describe('root route (/)', () => {
    it('redirects to /login when no token is present', async () => {
      const req = createNextRequest('http://localhost:3001/');
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/login');
    });

    it('redirects to /dashboard for an authenticated partner', async () => {
      const partnerToken = createFakeJwt({
        userId: 'p-1',
        email: 'p@test.com',
        exp: Math.floor(Date.now() / 1000) + 3600,
        iat: Math.floor(Date.now() / 1000),
        isPartner: true,
      });
      const req = createNextRequest('http://localhost:3001/', {
        [ACCESS_TOKEN_COOKIE]: partnerToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/dashboard');
    });

    it('redirects to /admin for an authenticated admin', async () => {
      const adminToken = createFakeJwt({
        userId: 'a-1',
        email: 'a@test.com',
        exp: Math.floor(Date.now() / 1000) + 3600,
        iat: Math.floor(Date.now() / 1000),
        isAdmin: true,
      });
      const req = createNextRequest('http://localhost:3001/', {
        [ACCESS_TOKEN_COOKIE]: adminToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/admin');
    });
  });

  // -----------------------------------------------------------------------
  // Expired token -- refresh flow
  // -----------------------------------------------------------------------
  describe('token refresh', () => {
    const expiredToken = createFakeJwt({
      userId: 'p-1',
      email: 'p@test.com',
      exp: Math.floor(Date.now() / 1000) - 60, // expired 1 minute ago
      iat: Math.floor(Date.now() / 1000) - 3660,
      isPartner: true,
    });

    const freshToken = createFakeJwt({
      userId: 'p-1',
      email: 'p@test.com',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000),
      isPartner: true,
    });

    it('refreshes an expired access token and continues to /dashboard', async () => {
      // Audit Ch10-W009: the rotated refresh token must itself look like a
      // JWT before the middleware persists it. We hand the upstream a fresh
      // signed JWT so the middleware accepts it.
      const newRefreshToken = createFakeJwt({
        userId: 'p-1',
        email: 'p@test.com',
        exp: Math.floor(Date.now() / 1000) + 7 * 24 * 3600,
        iat: Math.floor(Date.now() / 1000),
      });
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            success: true,
            data: { accessToken: freshToken, refreshToken: newRefreshToken },
          }),
        })
        // H-A8: after refresh, middleware fetches /auth/role-check.
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ data: { is_admin: false, is_partner: true } }),
        });

      const req = createNextRequest('http://localhost:3001/dashboard', {
        [ACCESS_TOKEN_COOKIE]: expiredToken,
        [REFRESH_TOKEN_COOKIE]: 'old-rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('next');

      // The response should have the refreshed cookies set
      expect(res.cookies.get('hk_access_token')?.value).toBe(freshToken);
      expect(res.cookies.get('hk_refresh_token')?.value).toBe(newRefreshToken);
    });

    it('redirects to /login when refresh fails', async () => {
      mockFetch.mockResolvedValueOnce({ ok: false, status: 401 });

      const req = createNextRequest('http://localhost:3001/dashboard', {
        [ACCESS_TOKEN_COOKIE]: expiredToken,
        [REFRESH_TOKEN_COOKIE]: 'old-rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/login');
    });

    it('allows access to /login when refresh fails', async () => {
      mockFetch.mockResolvedValueOnce({ ok: false, status: 401 });

      const req = createNextRequest('http://localhost:3001/login', {
        [ACCESS_TOKEN_COOKIE]: expiredToken,
        [REFRESH_TOKEN_COOKIE]: 'old-rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('next');
    });
  });

  // -----------------------------------------------------------------------
  // Non-partner/non-admin user
  // -----------------------------------------------------------------------
  describe('regular user (not partner or admin)', () => {
    const regularUserToken = createFakeJwt({
      userId: 'r-1',
      email: 'user@test.com',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000),
      // no isAdmin or isPartner
    });

    it('redirects to /login when accessing /dashboard', async () => {
      // H-A8: role-check confirms the user has no role — middleware redirects
      // to /login (clearing cookies en route).
      mockFetch.mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ data: { is_admin: false, is_partner: false } }),
      });
      const req = createNextRequest('http://localhost:3001/dashboard', {
        [ACCESS_TOKEN_COOKIE]: regularUserToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('redirect');
      expect(res.url).toContain('/login');
    });

    it('allows access to /login (public route)', async () => {
      const req = createNextRequest('http://localhost:3001/login', {
        [ACCESS_TOKEN_COOKIE]: regularUserToken,
        [REFRESH_TOKEN_COOKIE]: 'rt',
      });
      const res = await middleware(req as any);
      expect(res.type).toBe('next');
    });
  });
});
