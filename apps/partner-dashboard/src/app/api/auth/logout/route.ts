import { cookies } from 'next/headers';
import { NextRequest, NextResponse } from 'next/server';
import { ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE, clearAuthCookies } from '@/lib/auth';
import { API_URL } from '@/lib/config';
import { csrfTokenOk } from '@/lib/csrf';
import { fetchWithTimeout } from '@/lib/fetch';

/**
 * Server logout — calls the upstream API to invalidate the refresh-token
 * family + Redis session cache, then clears every cookie the dashboard sets
 * (audit Ch10-W045).
 *
 * Same-origin guard mirrors the refresh route — a cross-site POST that's
 * trying to log the user out would also be a CSRF surface.
 */
function isSameOriginFetch(request: NextRequest): boolean {
  const fetchSite = request.headers.get('sec-fetch-site');
  if (!fetchSite) return false;
  return fetchSite === 'same-origin' || fetchSite === 'same-site';
}

export async function POST(request: NextRequest) {
  if (!isSameOriginFetch(request)) {
    return NextResponse.json({ error: 'Cross-origin request rejected' }, { status: 403 });
  }

  // S2-N: every other mutation route enforces double-submit CSRF; logout
  // was the lone exception. Without this, a cross-tab attacker that
  // already has a valid auth cookie can force-logout the user via a
  // subdomain-issued POST that sets sec-fetch-site=same-site.
  if (!csrfTokenOk(request)) {
    return NextResponse.json({ error: 'CSRF token missing or mismatched' }, { status: 403 });
  }

  const cookieStore = await cookies();
  const accessToken = cookieStore.get(ACCESS_TOKEN_COOKIE)?.value;
  const refreshToken = cookieStore.get(REFRESH_TOKEN_COOKIE)?.value;

  if (refreshToken) {
    try {
      await fetchWithTimeout(`${API_URL}/api/v1/auth/logout`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        },
        body: JSON.stringify({ refreshToken }),
      });
    } catch {
      // Best-effort — clear cookies regardless. The upstream Redis cache
      // will purge the refresh family on its TTL even if this fetch fails.
    }
  }

  clearAuthCookies(cookieStore);

  return NextResponse.json({ success: true });
}
