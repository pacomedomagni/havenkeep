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

// H-A8: cached role assertion. The Edge middleware previously read
// is_admin / is_partner from the unverified JWT payload for routing,
// which meant a demoted user saw the admin/partner nav shell render
// for up to JWT_EXPIRES_IN (1 hour). The cookie carries the API's
// fresh DB-derived role decision; we trust the API and refresh the
// cookie on every request older than the TTL. HttpOnly so JS can't
// forge it; Secure in prod; SameSite=Lax matches the auth cookies.
const ROLE_COOKIE = 'hk_role_check'
const ROLE_CHECK_TTL_SECONDS = 30
const ROLE_CHECK_TIMEOUT_MS = 2_000

interface CachedRole {
  isAdmin: boolean
  isPartner: boolean
  cachedAt: number
}

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

/**
 * H-A8: read the cached role-check cookie. Returns null if the cookie
 * doesn't exist, is malformed, or has expired beyond ROLE_CHECK_TTL_SECONDS.
 */
function readRoleCookie(request: NextRequest): CachedRole | null {
  const raw = request.cookies.get(ROLE_COOKIE)?.value
  if (!raw) return null
  try {
    const decoded = JSON.parse(Buffer.from(raw, 'base64url').toString()) as CachedRole
    if (
      typeof decoded.isAdmin !== 'boolean' ||
      typeof decoded.isPartner !== 'boolean' ||
      typeof decoded.cachedAt !== 'number'
    ) {
      return null
    }
    if (Date.now() - decoded.cachedAt > ROLE_CHECK_TTL_SECONDS * 1000) {
      return null
    }
    return decoded
  } catch {
    return null
  }
}

function writeRoleCookie(response: NextResponse, cached: CachedRole) {
  const payload = Buffer.from(JSON.stringify(cached)).toString('base64url')
  const isProduction = process.env.NODE_ENV === 'production'
  response.cookies.set(ROLE_COOKIE, payload, {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: ROLE_CHECK_TTL_SECONDS,
  })
}

/**
 * H-A8: fetch fresh role state from the API's /auth/role-check endpoint.
 * Returns null on any failure so the caller can fall back to the
 * existing JWT-claim path. The 2s timeout matches the rest of the
 * Edge middleware's network ceiling — we'd rather skip role caching
 * than block navigation on a slow API.
 */
async function fetchFreshRole(accessToken: string): Promise<CachedRole | null> {
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), ROLE_CHECK_TIMEOUT_MS)
  try {
    const response = await fetch(`${API_URL}/api/v1/auth/role-check`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: controller.signal,
    }).finally(() => clearTimeout(timeoutId))
    if (!response.ok) return null
    const body = (await response.json().catch(() => null)) as
      | { data?: { is_admin?: boolean; is_partner?: boolean } }
      | null
    const data = body?.data
    if (
      !data ||
      typeof data.is_admin !== 'boolean' ||
      typeof data.is_partner !== 'boolean'
    ) {
      return null
    }
    return {
      isAdmin: data.is_admin,
      isPartner: data.is_partner,
      cachedAt: Date.now(),
    }
  } catch {
    return null
  }
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

  // Decode token for shape validation only — H-A8: we no longer trust
  // the unverified JWT body for role decisions. The fresh role check
  // below drives routing. We still need decodeJwtPayload to confirm
  // the token's general shape so a malformed cookie redirects to login.
  const payload = currentAccessToken ? decodeJwtPayload(currentAccessToken) : null
  if (!payload) {
    return redirectToLogin(request)
  }

  // H-A8: derive is_admin / is_partner from the API's fresh DB-derived
  // role-check, not from the unverified JWT body. Cached for
  // ROLE_CHECK_TTL_SECONDS so we don't hit the API on every nav. On
  // fetch failure we fall back to the JWT-claim values so a single
  // API hiccup doesn't lock everyone out — but the failure is
  // structurally bounded: every API call still re-derives via
  // requireAdmin / requirePartner middleware.
  let cachedRole = readRoleCookie(request)
  let roleCookieToWrite: CachedRole | null = null
  if (!cachedRole && currentAccessToken) {
    cachedRole = await fetchFreshRole(currentAccessToken)
    if (cachedRole) {
      roleCookieToWrite = cachedRole
    }
  }
  const isAdmin = cachedRole?.isAdmin ?? payload.isAdmin === true
  const isPartner = cachedRole?.isPartner ?? payload.isPartner === true

  // Non-admin/non-partner users cannot access the dashboard
  if (!isAdmin && !isPartner) {
    if (isPublicRoute) {
      ensureCsrfCookie(response, request)
      if (roleCookieToWrite) writeRoleCookie(response, roleCookieToWrite)
      return response
    }
    return redirectToLogin(request)
  }

  // Has valid token on public route — redirect based on role
  if (isPublicRoute && currentAccessToken) {
    const dest = getRoleRedirect({ isAdmin, isPartner })
    if (dest) {
      const redirectResponse = NextResponse.redirect(new URL(dest, request.url))
      if (roleCookieToWrite) writeRoleCookie(redirectResponse, roleCookieToWrite)
      return redirectResponse
    }
    return redirectToLogin(request)
  }

  // Route protection: /admin requires isAdmin, /dashboard requires isPartner
  if (pathname.startsWith('/admin') && !isAdmin) {
    return NextResponse.redirect(new URL('/unauthorized', request.url))
  }

  if (pathname.startsWith('/dashboard') && !isPartner) {
    return NextResponse.redirect(new URL('/unauthorized', request.url))
  }

  ensureCsrfCookie(response, request)
  if (roleCookieToWrite) writeRoleCookie(response, roleCookieToWrite)
  return response
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|api/|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
