import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

const API_URL = process.env.API_URL || 'http://localhost:3000';

const ACCESS_TOKEN_COOKIE = 'hk_access_token';
const REFRESH_TOKEN_COOKIE = 'hk_refresh_token';

export interface AuthUser {
  id: string;
  email: string;
  plan: string;
  isAdmin: boolean;
  isPartner: boolean;
}

interface TokenPayload {
  userId: string;
  email: string;
  exp: number;
  iat: number;
}

function decodeJwtPayload(token: string): TokenPayload | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    return payload;
  } catch {
    return null;
  }
}

export function isTokenExpired(token: string): boolean {
  const payload = decodeJwtPayload(token);
  if (!payload) return true;
  return payload.exp * 1000 < Date.now();
}

export async function getTokens(): Promise<{ accessToken: string; refreshToken: string } | null> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get(ACCESS_TOKEN_COOKIE)?.value;
  const refreshToken = cookieStore.get(REFRESH_TOKEN_COOKIE)?.value;

  if (!accessToken || !refreshToken) return null;
  return { accessToken, refreshToken };
}

export async function getUser(): Promise<AuthUser | null> {
  const tokens = await getTokens();
  if (!tokens) return null;

  const payload = decodeJwtPayload(tokens.accessToken);
  if (!payload) return null;

  // Fetch real user data from API to get accurate plan + isAdmin status
  try {
    const response = await fetch(`${API_URL}/api/v1/admin/me`, {
      headers: {
        Authorization: `Bearer ${tokens.accessToken}`,
        'Content-Type': 'application/json',
      },
      cache: 'no-store',
    });

    if (response.ok) {
      const data = await response.json();
      return {
        id: data.user.id,
        email: data.user.email,
        plan: data.user.plan,
        isAdmin: data.user.isAdmin,
        isPartner: data.user.isPartner ?? false,
      };
    }
  } catch {
    // Fall through to JWT-only data
  }

  // Fallback: use JWT data only (isAdmin/isPartner default to false for safety)
  return {
    id: payload.userId,
    email: payload.email,
    plan: 'free',
    isAdmin: false,
    isPartner: false,
  };
}

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
  cookieStore.delete(ACCESS_TOKEN_COOKIE);
  cookieStore.delete(REFRESH_TOKEN_COOKIE);
}

/**
 * Server-side API client that automatically includes JWT from cookies.
 */
export async function serverApiClient<T = any>(
  endpoint: string,
  options: {
    method?: string;
    body?: any;
    headers?: Record<string, string>;
  } = {}
): Promise<T> {
  const tokens = await getTokens();
  const { method = 'GET', body, headers = {} } = options;

  const fetchOptions: RequestInit = {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(tokens ? { Authorization: `Bearer ${tokens.accessToken}` } : {}),
      ...headers,
    },
    cache: 'no-store',
  };

  if (body && method !== 'GET') {
    fetchOptions.body = JSON.stringify(body);
  }

  const url = `${API_URL}${endpoint}`;
  const response = await fetch(url, fetchOptions);

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(
      errorData.error || errorData.message || `API request failed with status ${response.status}`
    );
  }

  return response.json();
}

export { ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE };
