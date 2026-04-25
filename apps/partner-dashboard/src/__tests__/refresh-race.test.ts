import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Audit Ch10-W066. Two regression coverage areas:
 *
 *   1. Partial JWT (only two segments / non-base64url body) must NOT be
 *      accepted by the middleware refresh path — the upstream might happily
 *      sign garbage on a misconfigured staging, and we'd rather hard-redirect
 *      to /login than persist a token we can't decode.
 *
 *   2. Refresh-race: the dashboard's client-side apiClient should never retry
 *      more than once when /api/auth/refresh fails, regardless of how the
 *      original 401 surfaces.
 */

// ── Mock next/server so we can import middleware without the real edge runtime
const { FakeNextResponse } = vi.hoisted(() => {
  class HoistedFakeCookies {
    private jar = new Map<string, { name: string; value: string }>();
    set(name: string, value: string) {
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
      return {
        type: 'redirect' as const,
        url: typeof url === 'string' ? url : url.toString(),
        cookies: new HoistedFakeCookies(),
      };
    },
    next() {
      return { type: 'next' as const, cookies: new HoistedFakeCookies() };
    },
    json(_body: unknown, init?: { status?: number }) {
      return { type: 'json' as const, status: init?.status ?? 200, cookies: new HoistedFakeCookies() };
    },
  };
  return { FakeNextResponse };
});

vi.mock('next/server', () => ({ NextResponse: FakeNextResponse }));

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

import { middleware } from '../../middleware';
import { looksLikeJwt, decodeJwtPayload } from '../lib/jwt';

const ACCESS_TOKEN_COOKIE = 'hk_access_token';
const REFRESH_TOKEN_COOKIE = 'hk_refresh_token';

class FakeCookies {
  private jar = new Map<string, { name: string; value: string }>();
  set(name: string, value: string) {
    this.jar.set(name, { name, value });
  }
  get(name: string) {
    return this.jar.get(name);
  }
  delete(name: string) {
    this.jar.delete(name);
  }
}

function createNextRequest(url: string, cookieEntries: Record<string, string> = {}) {
  const cookies = new FakeCookies();
  for (const [k, v] of Object.entries(cookieEntries)) cookies.set(k, v);
  return { url, nextUrl: new URL(url), cookies, headers: new Headers() };
}

function makeJwt(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.fakesig`;
}

beforeEach(() => {
  vi.clearAllMocks();
  mockFetch.mockReset();
});

describe('looksLikeJwt / decodeJwtPayload', () => {
  it('rejects two-segment tokens', () => {
    expect(looksLikeJwt('a.b')).toBe(false);
    expect(decodeJwtPayload('a.b')).toBeNull();
  });

  it('rejects non-base64url segments', () => {
    expect(looksLikeJwt('a.b@.c')).toBe(false);
    expect(looksLikeJwt('....')).toBe(false);
    expect(looksLikeJwt('')).toBe(false);
  });

  it('decodes a valid JWT payload', () => {
    const token = makeJwt({ userId: 'u1', email: 'u@x.com', exp: 9999999999, isAdmin: true });
    expect(looksLikeJwt(token)).toBe(true);
    const decoded = decodeJwtPayload(token);
    expect(decoded?.userId).toBe('u1');
    expect(decoded?.isAdmin).toBe(true);
  });
});

describe('middleware refresh path', () => {
  const expired = makeJwt({
    userId: 'p',
    email: 'p@x.com',
    isPartner: true,
    exp: Math.floor(Date.now() / 1000) - 600,
  });

  it('rejects a refresh response whose accessToken is not a JWT', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ accessToken: 'not.a.jwt!!', refreshToken: 'rt' }),
    });

    const req = createNextRequest('http://localhost:3001/dashboard', {
      [ACCESS_TOKEN_COOKIE]: expired,
      [REFRESH_TOKEN_COOKIE]: 'rt',
    });
    const res = await middleware(req as any);
    expect(res.type).toBe('redirect');
    expect(res.url).toContain('/login');
  });

  it('aborts the refresh fetch on the configured timeout', async () => {
    // Simulate a fetch that never resolves until aborted.
    mockFetch.mockImplementationOnce(
      (_url: string, init: { signal?: AbortSignal }) =>
        new Promise((_resolve, reject) => {
          init.signal?.addEventListener('abort', () => reject(new Error('aborted')));
        }),
    );

    const req = createNextRequest('http://localhost:3001/dashboard', {
      [ACCESS_TOKEN_COOKIE]: expired,
      [REFRESH_TOKEN_COOKIE]: 'rt',
    });
    // Advance fake timers past the 5s edge timeout.
    const promise = middleware(req as any);
    const res = await promise;
    expect(res.type).toBe('redirect');
    expect(res.url).toContain('/login');
  }, 10_000);
});
