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

  it('returns error on API failure', async () => {
    mockFetch.mockResolvedValueOnce(
      makeResponse(409, { error: 'Email already registered' })
    );
    const fd = makeFormData(VALID_FIELDS);
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'Email already registered' });
  });

  it('returns error on network failure', async () => {
    mockFetch.mockRejectedValueOnce(new Error('Network error'));
    const fd = makeFormData(VALID_FIELDS);
    const result = await signUp(fd);
    expect(result).toEqual({ error: 'Unable to connect to the server' });
  });

  it('calls setAuthCookies and redirects to /onboarding on success', async () => {
    mockFetch.mockResolvedValueOnce(
      makeResponse(201, { accessToken: 'at', refreshToken: 'rt' })
    );
    const fd = makeFormData(VALID_FIELDS);

    await expect(signUp(fd)).rejects.toThrow('NEXT_REDIRECT');

    expect(mockSetAuthCookies).toHaveBeenCalledOnce();
    expect(mockSetAuthCookies).toHaveBeenCalledWith('at', 'rt', mockCookieStore);
    expect(mockRedirect).toHaveBeenCalledWith('/onboarding');
  });

  it('uses the email prefix as fullName when fullName is not provided', async () => {
    mockFetch.mockResolvedValueOnce(
      makeResponse(201, { accessToken: 'at', refreshToken: 'rt' })
    );
    const fd = makeFormData({
      email: 'janedoe@example.com',
      password: 'Secret1!',
      confirmPassword: 'Secret1!',
      // fullName intentionally omitted
    });

    await expect(signUp(fd)).rejects.toThrow('NEXT_REDIRECT');

    const [, opts] = mockFetch.mock.calls[0] as [string, RequestInit];
    const body = JSON.parse(opts.body as string);
    expect(body.fullName).toBe('janedoe');
  });
});
