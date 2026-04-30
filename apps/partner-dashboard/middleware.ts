import { NextResponse, type NextRequest } from 'next/server'

// API_URL must be configured outside of test/dev. Edge middleware can't import
// from `@/lib/config` (Edge runtime can't run the throw-on-load there), so the
// guard is duplicated here for clarity.
const API_URL = (() => {
  const value = process.env.API_URL
  if (value && value.trim().length > 0) return value
  if (process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development') {
    return 'http://localhost:3000'
  }
  // In a misconfigured production we'd rather hard-redirect everyone to /login
  // than silently route refresh calls into the void. Returning an unreachable
  // host triggers the catch path below on every middleware run.
  return 'http://api.invalid'
})()

// NOTE: ACCESS_TOKEN_COOKIE / REFRESH_TOKEN_COOKIE / CSRF_COOKIE are also
// defined in src/lib/auth.ts. We can't import that here because auth.ts pulls
// in `next/headers` and `next/navigation` at the top level, which the Edge
// runtime forbids.
const ACCESS_TOKEN_COOKIE = 'hk_access_token'
const REFRESH_TOKEN_COOKIE = 'hk_refresh_token'
const CSRF_COOKIE = 'csrf_token'

const REFRESH_TIMEOUT_MS = 5_000

// Edge-runtime decoder. The Express API is the only signature verifier — this
// path only short-circuits obvious tampering and drives client-side routing
// (audit Ch10-W008).
function looksLikeJwt(token: string): boolean {
  if (token.length === 0 || token.length > 4096) return false
  const parts = token.split('.')
  if (parts.length !== 3) return false
  const re = /^[A-Za-z0-9_-]+$/
  return parts.every((p) => p.length > 0 && re.test(p))
}

function decodeJwtPayload(
  token: string
): { userId: string; email: string; exp: number; isAdmin?: boolean; isPartner?: boolean } | null {
  if (!looksLikeJwt(token)) return null
  try {
    return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString())
  } catch {
    return null
  }
}

function isTokenExpired(token: string): boolean {
  const payload = decodeJwtPayload(token)
  if (!payload || typeof payload.exp !== 'number') return true
  return payload.exp * 1000 < Date.now() + 30_000
}

/**
 * Generate a CSRF token cookie if one isn't set. The proxy enforces
 * double-submit on every mutation, so the cookie has to exist before the
 * first form submit (audit Ch10-W028).
 */
function ensureCsrfCookie(response: NextResponse, request: NextRequest) {
  const existing = request.cookies.get(CSRF_COOKIE)?.value
  if (existing && existing.length >= 16) return
  const bytes = new Uint8Array(24)
  crypto.getRandomValues(bytes)
  const token = Buffer.from(bytes).toString('base64url')
  const isProduction = process.env.NODE_ENV === 'production'
  response.cookies.set(CSRF_COOKIE, token, {
    httpOnly: false, // double-submit pattern needs JS read access
    secure: isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 60 * 24 * 7,
  })
}

function redirectToLogin(request: NextRequest): NextResponse {
  const response = NextResponse.redirect(new URL('/login', request.url))
  response.cookies.delete(ACCESS_TOKEN_COOKIE)
  response.cookies.delete(REFRESH_TOKEN_COOKIE)
  response.cookies.delete(CSRF_COOKIE)
  return response
}

function getRoleRedirect(payload: { isAdmin?: boolean; isPartner?: boolean }): string | null {
  if (payload.isAdmin) return '/admin'
  if (payload.isPartner) return '/dashboard'
  return null
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Root route — always redirect (avoids standalone clientModules bug)
  if (pathname === '/') {
    const accessToken = request.cookies.get(ACCESS_TOKEN_COOKIE)?.value
    if (accessToken && !isTokenExpired(accessToken)) {
      const payload = decodeJwtPayload(accessToken)
      if (payload) {
        const dest = getRoleRedirect(payload)
        if (dest) {
          return NextResponse.redirect(new URL(dest, request.url))
        }
      }
      return redirectToLogin(request)
    }
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // Public routes — no auth required
  const isPublicRoute =
    pathname === '/login' ||
    pathname === '/signup' ||
    pathname === '/forgot-password' ||
    pathname.startsWith('/reset-password') ||
    pathname === '/unauthorized'

  const accessToken = request.cookies.get(ACCESS_TOKEN_COOKIE)?.value
  const refreshToken = request.cookies.get(REFRESH_TOKEN_COOKIE)?.value

  // No tokens at all
  if (!accessToken && !refreshToken) {
    if (isPublicRoute) {
      const res = NextResponse.next()
      ensureCsrfCookie(res, request)
      return res
    }
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // Check if access token is expired and needs refresh
  let currentAccessToken = accessToken
  let response = NextResponse.next()

  if (!accessToken || isTokenExpired(accessToken)) {
    if (refreshToken) {
      try {
        // Hard timeout on the refresh fetch — without it, a stuck upstream
        // would hang every page request indefinitely (audit Ch10-W007).
        const controller = new AbortController()
        const timeoutId = setTimeout(() => controller.abort(), REFRESH_TIMEOUT_MS)
        const refreshResponse = await fetch(`${API_URL}/api/v1/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken }),
          signal: controller.signal,
        }).finally(() => clearTimeout(timeoutId))

        if (refreshResponse.ok) {
          // H-A7: API wraps responses in { success, data: { ... } }; unwrap
          // before validating shape.
          const body = await refreshResponse.json().catch(() => ({}))
          const data = body?.data ?? {}
          // Validate the refresh response before persisting (audit Ch10-W009).
          // Anything that doesn't look like a JWT goes back to the login page;
          // we'd rather force a re-login than store junk in a cookie.
          if (typeof data.accessToken !== 'string' || !looksLikeJwt(data.accessToken)) {
            return redirectToLogin(request)
          }
          currentAccessToken = data.accessToken

          response = NextResponse.next()
          const isProduction = process.env.NODE_ENV === 'production'

          response.cookies.set(ACCESS_TOKEN_COOKIE, data.accessToken, {
            httpOnly: true,
            secure: isProduction,
            sameSite: 'lax',
            path: '/',
            maxAge: 60 * 60,
          })

          // Store the rotated refresh token (API uses token rotation)
          if (typeof data.refreshToken === 'string' && looksLikeJwt(data.refreshToken)) {
            response.cookies.set(REFRESH_TOKEN_COOKIE, data.refreshToken, {
              httpOnly: true,
              secure: isProduction,
              sameSite: 'lax',
              path: '/',
              maxAge: 60 * 60 * 24 * 7,
            })
          }
        } else {
          if (isPublicRoute) {
            const res = NextResponse.next()
            ensureCsrfCookie(res, request)
            return res
          }
          return redirectToLogin(request)
        }
      } catch {
        if (isPublicRoute) {
          const res = NextResponse.next()
          ensureCsrfCookie(res, request)
          return res
        }
        return redirectToLogin(request)
      }
    } else {
      if (isPublicRoute) {
        const res = NextResponse.next()
        ensureCsrfCookie(res, request)
        return res
      }
      return redirectToLogin(request)
    }
  }

  // Decode token for role-based routing
  const payload = currentAccessToken ? decodeJwtPayload(currentAccessToken) : null
  if (!payload) {
    return redirectToLogin(request)
  }

  // Non-admin/non-partner users cannot access the dashboard
  if (!payload.isAdmin && !payload.isPartner) {
    if (isPublicRoute) {
      ensureCsrfCookie(response, request)
      return response
    }
    return redirectToLogin(request)
  }

  // Has valid token on public route — redirect based on role
  if (isPublicRoute && currentAccessToken) {
    const dest = getRoleRedirect(payload)
    if (dest) {
      return NextResponse.redirect(new URL(dest, request.url))
    }
    return redirectToLogin(request)
  }

  // Route protection: /admin requires isAdmin, /dashboard requires isPartner
  if (pathname.startsWith('/admin') && payload.isAdmin !== true) {
    return NextResponse.redirect(new URL('/unauthorized', request.url))
  }

  if (pathname.startsWith('/dashboard') && payload.isPartner !== true) {
    return NextResponse.redirect(new URL('/unauthorized', request.url))
  }

  ensureCsrfCookie(response, request)
  return response
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|api/|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
