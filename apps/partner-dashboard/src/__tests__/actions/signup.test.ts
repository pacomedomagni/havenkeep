import { describe, it, expect, vi, beforeEach } from 'vitest';

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
import { signUp } from '@/app/signup/actions';

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

const VALID_FIELDS = {
  email: 'user@example.com',
  password: 'Secret1!',
  confirmPassword: 'Secret1!',
  fullName: 'Jane Doe',
  companyName: 'Doe Realty',
  partnerType: 'realtor',
};

describe('signUp', () => {
  it('returns error for an invalid email', async () => {
    const fd = makeFormData({ ...VALID_FIELDS, email: 'not-an-email' });
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'Please enter a valid email address' });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('returns error when passwords do not match', async () => {
    const fd = makeFormData({
      ...VALID_FIELDS,
      confirmPassword: 'Different1!',
    });
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'Passwords do not match' });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('returns error for a password shorter than 8 characters', async () => {
    const fd = makeFormData({
      ...VALID_FIELDS,
      password: 'Sh1!',
      confirmPassword: 'Sh1!',
    });
    const result = await signUp(fd);
    expect(result).toMatchObject({ error: expect.stringContaining('8 characters') });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('returns error for a weak password missing a special character', async () => {
    const fd = makeFormData({
      ...VALID_FIELDS,
      password: 'Password1',
      confirmPassword: 'Password1',
    });
    const result = await signUp(fd);
    expect(result).toMatchObject({ error: expect.stringContaining('special character') });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('returns generic conflict message on 409 (audit Ch10-W011)', async () => {
    mockFetch.mockResolvedValueOnce(
      makeResponse(409, { error: 'Some upstream message we should not surface' })
    );
    const fd = makeFormData(VALID_FIELDS);
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'An account with that email already exists.' });
  });

  it('returns error on network failure', async () => {
    mockFetch.mockRejectedValueOnce(new Error('Network error'));
    const fd = makeFormData(VALID_FIELDS);
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'Unable to connect to the server' });
  });

  it('calls setAuthCookies and redirects to /dashboard on success', async () => {
    // Two fetch calls: /auth/register, then /partners/register.
    mockFetch
      .mockResolvedValueOnce(
        makeResponse(201, { success: true, data: { accessToken: 'at', refreshToken: 'rt' } })
      )
      .mockResolvedValueOnce(makeResponse(201, { success: true, data: {} }));
    const fd = makeFormData(VALID_FIELDS);

    await expect(signUp(fd)).rejects.toThrow('NEXT_REDIRECT');

    expect(mockSetAuthCookies).toHaveBeenCalledOnce();
    expect(mockSetAuthCookies).toHaveBeenCalledWith('at', 'rt', mockCookieStore);
    expect(mockRedirect).toHaveBeenCalledWith('/dashboard');
  });

  // Audit Ch10-W013: explicit fullName is required — we no longer auto-derive
  // it from the email local-part, which had two problems: it leaked the email
  // prefix into product copy, and it accepted accounts with no human-readable
  // name on file.
  it('rejects signup when fullName is missing', async () => {
    const fd = makeFormData({
      email: 'janedoe@example.com',
      password: 'Secret1!',
      confirmPassword: 'Secret1!',
      companyName: 'Doe Realty',
      partnerType: 'realtor',
    });
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'Full name is required' });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('rejects signup when companyName is missing', async () => {
    const fd = makeFormData({
      email: 'janedoe@example.com',
      password: 'Secret1!',
      confirmPassword: 'Secret1!',
      fullName: 'Jane Doe',
    });
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'Company or business name is required' });
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
