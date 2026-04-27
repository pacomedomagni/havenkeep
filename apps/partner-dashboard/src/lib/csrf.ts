import type { NextRequest } from 'next/server';

// Double-submit CSRF check shared between the API proxy and the logout
// route. The dashboard sets `csrf_token` cookie on login; the client must
// echo it in the `x-csrf-token` header on every mutation.
export const CSRF_COOKIE = 'csrf_token';
export const CSRF_HEADER = 'x-csrf-token';

export function csrfTokenOk(request: NextRequest): boolean {
  const cookieToken = request.cookies.get(CSRF_COOKIE)?.value;
  const headerToken = request.headers.get(CSRF_HEADER);
  if (!cookieToken || !headerToken) return false;
  if (cookieToken.length < 16 || headerToken.length < 16) return false;
  if (cookieToken.length !== headerToken.length) return false;
  // Constant-time-ish byte comparison.
  let same = 0;
  for (let i = 0; i < cookieToken.length; i++) {
    same |= cookieToken.charCodeAt(i) ^ headerToken.charCodeAt(i);
  }
  return same === 0;
}
