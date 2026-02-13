import { NextResponse, type NextRequest } from 'next/server'

const API_URL = process.env.API_URL || 'http://localhost:3000'
const ACCESS_TOKEN_COOKIE = 'hk_access_token'
const REFRESH_TOKEN_COOKIE = 'hk_refresh_token'

function decodeJwtPayload(token: string): { userId: string; email: string; exp: number } | null {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString())
  } catch {
    return null
  }
}

function isTokenExpired(token: string): boolean {
  const payload = decodeJwtPayload(token)
  if (!payload) return true
  // Consider expired 30 seconds early to avoid edge cases
  return payload.exp * 1000 < Date.now() + 30000
}

function redirectToLogin(request: NextRequest): NextResponse {
  const response = NextResponse.redirect(new URL('/login', request.url))
  response.cookies.delete(ACCESS_TOKEN_COOKIE)
  response.cookies.delete(REFRESH_TOKEN_COOKIE)
  return response
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Root route — always redirect (avoids standalone clientModules bug)
  if (pathname === '/') {
    const accessToken = request.cookies.get(ACCESS_TOKEN_COOKIE)?.value
    if (accessToken && !isTokenExpired(accessToken)) {
      return NextResponse.redirect(new URL('/dashboard', request.url))
    }
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // Public routes — no auth required
  const isPublicRoute =
    pathname === '/login' ||
    pathname === '/signup' ||
    pathname === '/unauthorized'

  const accessToken = request.cookies.get(ACCESS_TOKEN_COOKIE)?.value
  const refreshToken = request.cookies.get(REFRESH_TOKEN_COOKIE)?.value

  // No tokens at all
  if (!accessToken && !refreshToken) {
    if (isPublicRoute) return NextResponse.next()
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // Check if access token is expired and needs refresh
  let currentAccessToken = accessToken
  let response = NextResponse.next()

  if (!accessToken || isTokenExpired(accessToken)) {
    if (refreshToken) {
      try {
        const refreshResponse = await fetch(`${API_URL}/api/v1/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken }),
        })

        if (refreshResponse.ok) {
          const data = await refreshResponse.json()
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
        } else {
          if (isPublicRoute) return NextResponse.next()
          return redirectToLogin(request)
        }
      } catch {
        if (isPublicRoute) return NextResponse.next()
        return redirectToLogin(request)
      }
    } else {
      if (isPublicRoute) return NextResponse.next()
      return redirectToLogin(request)
    }
  }

  // Has valid token on public route — redirect to dashboard
  if (isPublicRoute && currentAccessToken) {
    return NextResponse.redirect(new URL('/dashboard', request.url))
  }

  // Decode token for admin check
  const payload = currentAccessToken ? decodeJwtPayload(currentAccessToken) : null
  if (!payload) {
    return redirectToLogin(request)
  }

  return response
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|api/|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
