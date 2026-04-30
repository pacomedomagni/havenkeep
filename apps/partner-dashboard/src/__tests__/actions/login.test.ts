import { describe, it, expect, vi, beforeEach } from 'vitest';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function createFakeJwt(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.fakesignature`;
}

// ---------------------------------------------------------------------------
// Mocks — must be declared before importing the module under test
// ---------------------------------------------------------------------------

const mockCookieStore = {
  get: vi.fn(),
  set: vi.fn(),
  delete: vi.fn(),
};

vi.mock('next/headers', () => ({
  cookies: vi.fn(async () => mockCookieStore),
}));

const mockRedirect = vi.fn();
vi.mock('next/navigation', () => ({
  redirect: vi.fn().mockImplementation((url: string) => {
    mockRedirect(url);
    throw new Error('NEXT_REDIRECT');
  }),
}));

const mockSetAuthCookies = vi.fn();
vi.mock('@/lib/auth', () => ({
  setAuthCookies: (...args: unknown[]) => mockSetAuthCookies(...args),
}));

vi.mock('@/lib/config', () => ({
  API_URL: 'http://localhost:3000',
  PROXY_FETCH_TIMEOUT_MS: 30_000,
  CLIENT_FETCH_TIMEOUT_MS: 25_000,
}));

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

// ---------------------------------------------------------------------------
// Import module under test (after mocks)
// ---------------------------------------------------------------------------
import { signIn } from '@/app/login/actions';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
});

function makeFormData(fields: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [key, value] of Object.entries(fields)) {
    fd.append(key, value);
  }
  return fd;
}

function makeResponse(status: number, body: unknown): Response {
  const ok = status >= 200 && status < 300;
  return {
    ok,
    status,
    json: async () => body,
  } as unknown as Response;
}

describe('signIn', () => {
  it('returns error when email is missing', async () => {
    const fd = makeFormData({ password: 'Secret1!' });
    const result = await signIn(null, fd);
    expect(result).toEqual({ error: 'Email and password are required' });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('returns error when password is missing', async () => {
    const fd = makeFormData({ email: 'user@example.com' });
    const result = await signIn(null, fd);
    expect(result).toEqual({ error: 'Email and password are required' });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('returns generic error on invalid credentials (audit Ch10-W015)', async () => {
    // The login action no longer echoes upstream messages — the user always
    // gets the same generic "incorrect" copy regardless of which field is
    // wrong.
    mockFetch.mockResolvedValueOnce(
      makeResponse(401, { error: 'Some upstream message we should not surface' })
    );
    const fd = makeFormData({ email: 'user@example.com', password: 'wrong' });
    const result = await signIn(null, fd);
    expect(result).toEqual({ error: 'The email or password is incorrect.' });
  });

  it('returns error for non-partner/non-admin user', async () => {
    const accessToken = createFakeJwt({ isAdmin: false });
    mockFetch.mockResolvedValueOnce(
      makeResponse(200, {
        success: true,
        data: {
          accessToken,
          refreshToken: 'rt',
          user: { is_admin: false, is_partner: false },
        },
      })
    );
    const fd = makeFormData({ email: 'user@example.com', password: 'Secret1!' });
    const result = await signIn(null, fd);
    expect(result).toEqual({ error: 'Access restricted to partners and administrators' });
  });

  it('calls setAuthCookies on successful login', async () => {
    const accessToken = createFakeJwt({ isAdmin: false, isPartner: true });
    mockFetch.mockResolvedValueOnce(
      makeResponse(200, {
        success: true,
        data: {
          accessToken,
          refreshToken: 'rt',
          user: { is_admin: false, is_partner: true },
        },
      })
    );
    const fd = makeFormData({ email: 'partner@example.com', password: 'Secret1!' });

    await expect(signIn(null, fd)).rejects.toThrow('NEXT_REDIRECT');

    expect(mockSetAuthCookies).toHaveBeenCalledOnce();
    expect(mockSetAuthCookies).toHaveBeenCalledWith(accessToken, 'rt', mockCookieStore);
  });

  it('redirects to /dashboard for a partner user', async () => {
    const accessToken = createFakeJwt({ isAdmin: false });
    mockFetch.mockResolvedValueOnce(
      makeResponse(200, {
        success: true,
        data: {
          accessToken,
          refreshToken: 'rt',
          user: { is_admin: false, is_partner: true },
        },
      })
    );
    const fd = makeFormData({ email: 'partner@example.com', password: 'Secret1!' });

    await expect(signIn(null, fd)).rejects.toThrow('NEXT_REDIRECT');
    expect(mockRedirect).toHaveBeenCalledWith('/dashboard');
  });

  it('redirects to /admin for an admin user', async () => {
    const accessToken = createFakeJwt({ isAdmin: true });
    mockFetch.mockResolvedValueOnce(
      makeResponse(200, {
        success: true,
        data: {
          accessToken,
          refreshToken: 'rt',
          user: { is_admin: true, is_partner: false },
        },
      })
    );
    const fd = makeFormData({ email: 'admin@example.com', password: 'Secret1!' });

    await expect(signIn(null, fd)).rejects.toThrow('NEXT_REDIRECT');
    expect(mockRedirect).toHaveBeenCalledWith('/admin');
  });

  it('returns error on network failure', async () => {
    mockFetch.mockRejectedValueOnce(new Error('Network failure'));
    const fd = makeFormData({ email: 'user@example.com', password: 'Secret1!' });
    const result = await signIn(null, fd);
    expect(result).toEqual({ error: 'Unable to connect to the server' });
  });
});
