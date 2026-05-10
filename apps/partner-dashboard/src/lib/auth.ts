import { cache } from 'react';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { API_URL } from './config';
import { fetchWithTimeout } from './fetch';
import { decodeJwtPayload, isTokenExpired, looksLikeJwt } from './jwt';

const ACCESS_TOKEN_COOKIE = 'hk_access_token';
const REFRESH_TOKEN_COOKIE = 'hk_refresh_token';
// C0-27: short-lived (5 min) cookie that carries the API's
// `mfa_token` between /login submit and /login/mfa code submit.
// httpOnly so client JS never touches it; the user-side state is
// just "you're on the MFA page now."
const MFA_TOKEN_COOKIE = 'hk_mfa_token';
const CSRF_COOKIE = 'csrf_token';
// Audit Ch10-W045: every cookie the dashboard sets gets cleared on logout.
// H26: include the role-check cache. Without this, signing out and
// signing in as a different user would briefly render the previous
// user's role-based nav shell (30s TTL) before the next request
// refreshed the cookie.
const ROLE_CHECK_COOKIE = 'hk_role_check';
const CLEARABLE_COOKIES = [ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE, CSRF_COOKIE, MFA_TOKEN_COOKIE, ROLE_CHECK_COOKIE] as const;

export interface AuthUser {
  id: string;
  email: string;
  plan: string;
  isAdmin: boolean;
  isPartner: boolean;
}

export { isTokenExpired, looksLikeJwt, decodeJwtPayload };

export async function getTokens(): Promise<{ accessToken: string; refreshToken: string } | null> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get(ACCESS_TOKEN_COOKIE)?.value;
  const refreshToken = cookieStore.get(REFRESH_TOKEN_COOKIE)?.value;

  if (!accessToken || !refreshToken) return null;
  return { accessToken, refreshToken };
}

/**
 * Fetch the authenticated user. Three failure modes:
 *   - no tokens / 401              -> null (caller redirects to /login)
 *   - 5xx / network / parse error  -> throws ApiUnavailableError so callers
 *                                     can render a real error UI rather than
 *                                     bouncing the user to /login on every
 *                                     transient outage (audit Ch10-W047).
 *
 * Wrapped in React `cache()` so a single render that calls `requireAuth`
 * + `requireAdmin` + a layout-level lookup hits the upstream once
 * (audit Ch10-W060).
 */
export class ApiUnavailableError extends Error {
  constructor(message = 'API unavailable') {
    super(message);
    this.name = 'ApiUnavailableError';
  }
}

async function getUserUncached(): Promise<AuthUser | null> {
  const tokens = await getTokens();
  if (!tokens) return null;

  if (!looksLikeJwt(tokens.accessToken)) return null;
  if (isTokenExpired(tokens.accessToken, 0)) return null;

  let response: Response;
  try {
    response = await fetchWithTimeout(`${API_URL}/api/v1/admin/me`, {
      headers: {
        Authorization: `Bearer ${tokens.accessToken}`,
        'Content-Type': 'application/json',
      },
      cache: 'no-store',
    });
  } catch {
    throw new ApiUnavailableError();
  }

  if (response.status === 401) return null;
  if (!response.ok) throw new ApiUnavailableError();

  try {
    const data = await response.json();
    if (!data?.data) throw new ApiUnavailableError('Malformed user response');
    return {
      id: data.data.id,
      email: data.data.email,
      plan: data.data.plan,
      isAdmin: !!data.data.is_admin,
      isPartner: !!data.data.is_partner,
    };
  } catch (err) {
    if (err instanceof ApiUnavailableError) throw err;
    throw new ApiUnavailableError('Malformed user response');
  }
}

export const getUser = cache(getUserUncached);

export async function requireAuth(): Promise<AuthUser> {
  const user = await getUser();
  if (!user) {
    redirect('/login');
  }
  return user;
}

export async function requireAdmin(): Promise<AuthUser> {
  const user = await requireAuth();
  if (!user.isAdmin) {
    redirect('/unauthorized');
  }
  return user;
}

/**
 * Layout-level role gate. Use in a server-component layout to enforce the
 * role for every nested route, so a forgotten `requireAdmin` in a leaf page
 * doesn't quietly leak admin UI to non-admins (audit Ch10-W044).
 */
export const requireRole = (role: 'admin' | 'partner' | 'partner-or-admin'): Promise<AuthUser> => {
  switch (role) {
    case 'admin':
      return requireAdmin();
    case 'partner':
      return requirePartner();
    case 'partner-or-admin':
      return requirePartnerOrAdmin();
  }
};

export async function requirePartner(): Promise<AuthUser> {
  const user = await requireAuth();
  if (!user.isPartner) {
    redirect('/unauthorized');
  }
  return user;
}

export async function requirePartnerOrAdmin(): Promise<AuthUser> {
  const user = await requireAuth();
  if (!user.isAdmin && !user.isPartner) {
    redirect('/unauthorized');
  }
  return user;
}

export function setAuthCookies(
  accessToken: string,
  refreshToken: string,
  cookieStore: Awaited<ReturnType<typeof cookies>>
) {
  const isProduction = process.env.NODE_ENV === 'production';

  cookieStore.set(ACCESS_TOKEN_COOKIE, accessToken, {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 60, // 1 hour
  });

  cookieStore.set(REFRESH_TOKEN_COOKIE, refreshToken, {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 60 * 24 * 7, // 7 days
  });
}

export function clearAuthCookies(cookieStore: Awaited<ReturnType<typeof cookies>>) {
  for (const name of CLEARABLE_COOKIES) {
    cookieStore.delete(name);
  }
}

// C0-27: helpers for the MFA hand-off cookie. /login → /login/mfa
// flow only.
export function setMfaTokenCookie(
  token: string,
  cookieStore: Awaited<ReturnType<typeof cookies>>,
) {
  const isProduction = process.env.NODE_ENV === 'production';
  cookieStore.set(MFA_TOKEN_COOKIE, token, {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: 5 * 60, // 5 min — matches the API's CHALLENGE_TTL_SECONDS.
  });
}

export function readMfaTokenCookie(
  cookieStore: Awaited<ReturnType<typeof cookies>>,
): string | undefined {
  return cookieStore.get(MFA_TOKEN_COOKIE)?.value;
}

export function clearMfaTokenCookie(
  cookieStore: Awaited<ReturnType<typeof cookies>>,
) {
  cookieStore.delete(MFA_TOKEN_COOKIE);
}

/**
 * Server-side API client that automatically includes JWT from cookies.
 *
 * Errors are rewritten to a small set of generic messages so internal
 * details (stack-trace tail, DB driver text, internal route names) never
 * leak to admin UI (audit Ch10-W046).
 */
export class ApiError extends Error {
  constructor(
    message: string,
    public status: number
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

function genericMessageForStatus(status: number): string {
  if (status === 401) return 'Your session has expired. Please sign in again.';
  if (status === 403) return 'You do not have permission to perform that action.';
  if (status === 404) return 'The requested record could not be found.';
  if (status === 409) return 'That action conflicts with the current state.';
  if (status === 422) return 'The request was rejected by the server.';
  if (status === 429) return 'Too many requests. Please slow down and try again.';
  if (status >= 500) return 'The service is temporarily unavailable. Please try again.';
  return 'The request was rejected by the server.';
}

export async function serverApiClient<T = unknown>(
  endpoint: string,
  options: {
    method?: string;
    body?: unknown;
    headers?: Record<string, string>;
  } = {}
): Promise<T> {
  const tokens = await getTokens();
  const { method = 'GET', body, headers = {} } = options;

  // H25: forward an idempotency key on every mutation so a retry from
  // the Next.js server action layer can't double-write. The dashboard
  // owns the lifecycle of these calls; the API's idempotency
  // middleware then transparently replays the cached response.
  // crypto.randomUUID is available on globalThis in both Node 18+
  // and Edge runtimes.
  const isMutation = method !== 'GET' && method !== 'HEAD' && method !== 'OPTIONS';
  const autoIdempotencyKey =
    isMutation && !headers['Idempotency-Key'] && !headers['idempotency-key']
      ? globalThis.crypto.randomUUID()
      : undefined;

  const fetchOptions: RequestInit = {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(tokens ? { Authorization: `Bearer ${tokens.accessToken}` } : {}),
      ...(autoIdempotencyKey ? { 'Idempotency-Key': autoIdempotencyKey } : {}),
      ...headers,
    },
    cache: 'no-store',
  };

  if (body !== undefined && method !== 'GET') {
    fetchOptions.body = JSON.stringify(body);
  }

  const url = `${API_URL}${endpoint}`;
  let response: Response;
  try {
    response = await fetchWithTimeout(url, fetchOptions);
  } catch {
    throw new ApiError(genericMessageForStatus(503), 503);
  }

  if (!response.ok) {
    // Drain the body so we don't leak the upstream's verbose JSON, but read
    // it for logging. The thrown message is the generic one.
    await response.json().catch(() => ({}));
    throw new ApiError(genericMessageForStatus(response.status), response.status);
  }

  return response.json();
}

export { ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE, CSRF_COOKIE };
