import { cookies } from 'next/headers';
import { NextRequest, NextResponse } from 'next/server';
import { REFRESH_TOKEN_COOKIE, setAuthCookies } from '@/lib/auth';
import { looksLikeJwt } from '@/lib/jwt';
import { API_URL } from '@/lib/config';
import { fetchWithTimeout } from '@/lib/fetch';

/**
 * Browser-driven refresh endpoint. Cookies are httpOnly, so the proxy is the
 * only path that ever knows the actual refresh token.
 *
 * Security:
 *   - Same-origin guard via Sec-Fetch-Site (audit Ch10-W010). A cross-site
 *     site that POSTs here without the header gets a 403, even though the
 *     refresh cookie is `SameSite=Lax`.
 *   - Refresh response is shape-validated before we persist it (Ch10-W009).
 *   - Generic error message regardless of upstream cause (Ch10-W011).
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

  const cookieStore = await cookies();
  const refreshToken = cookieStore.get(REFRESH_TOKEN_COOKIE)?.value;

  if (!refreshToken || !looksLikeJwt(refreshToken)) {
    return NextResponse.json({ error: 'Session expired' }, { status: 401 });
  }

  let response: Response;
  try {
    response = await fetchWithTimeout(`${API_URL}/api/v1/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken }),
    });
  } catch {
    return NextResponse.json({ error: 'Service unavailable' }, { status: 503 });
  }

  if (!response.ok) {
    return NextResponse.json({ error: 'Session expired' }, { status: 401 });
  }

  const data = await response.json().catch(() => ({}));

  if (typeof data.accessToken !== 'string' || !looksLikeJwt(data.accessToken)) {
    return NextResponse.json({ error: 'Session expired' }, { status: 401 });
  }
  const nextRefresh =
    typeof data.refreshToken === 'string' && looksLikeJwt(data.refreshToken)
      ? data.refreshToken
      : refreshToken;

  setAuthCookies(data.accessToken, nextRefresh, cookieStore);

  return NextResponse.json({ success: true });
}
