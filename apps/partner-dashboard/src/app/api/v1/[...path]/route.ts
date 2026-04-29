import { NextRequest, NextResponse } from 'next/server';
import { API_URL } from '@/lib/config';
import { ACCESS_TOKEN_COOKIE } from '@/lib/auth';
import { csrfTokenOk } from '@/lib/csrf';

// ─── Hardening rules (audit Ch10-W001..W005, W028) ───
//
// 1. Path segments are validated against a strict allowlist regex. `..`,
//    encoded slashes, query-style chars, etc. are rejected with 400.
// 2. Browser cookies and arbitrary headers are NOT forwarded upstream. The
//    proxy mints its own Authorization header from the access-token cookie
//    and forwards only an explicit allowlist (Content-Type, Accept, etc.).
// 3. Mutating methods require a same-origin Fetch (Sec-Fetch-Site === 'same-origin'
//    or 'same-site') AND a double-submit CSRF token. The cookie-based session
//    means a CORS-evading cross-origin request would otherwise be a confused-
//    deputy hole.
// 4. Upstream response headers are reduced to a small allowlist (no
//    Set-Cookie / CORS leak from upstream).

const SAFE_SEGMENT = /^[A-Za-z0-9._~-]{1,128}$/;
const FORWARDABLE_REQUEST_HEADERS = new Set([
  'content-type',
  'accept',
  'accept-language',
  'x-request-id',
  'x-idempotency-key',
  'idempotency-key',
]);
const FORWARDABLE_RESPONSE_HEADERS = new Set([
  'content-type',
  'cache-control',
  'etag',
  'last-modified',
  'x-request-id',
]);
const MUTATION_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

function buildUpstreamUrl(pathParts: string[], search: string): string | null {
  for (const segment of pathParts) {
    // Decode once, then validate. If decoding produces a different value the
    // raw was already URL-encoded — that's only safe if the decoded form also
    // passes the allowlist.
    const decoded = decodeURIComponent(segment);
    if (!SAFE_SEGMENT.test(segment) || !SAFE_SEGMENT.test(decoded)) {
      return null;
    }
  }
  return `${API_URL}/api/v1/${pathParts.join('/')}${search}`;
}

// 4.2: CSRF cross-app invariant — read this before changing the proxy.
//
// The upstream Express API's `validateCsrfToken` middleware bypasses CSRF
// when the request carries no cookies (the protection model is "cookies
// in flight = browser session; no cookies = pure API client"). The
// dashboard's proxy DELIBERATELY strips every cookie before forwarding
// upstream, then performs its OWN double-submit CSRF check at the proxy
// layer (see `csrfTokenOk`). Two consequences:
//
//   1. Adding `cookie` to FORWARDABLE_REQUEST_HEADERS would route the
//      browser's CSRF cookie to the upstream API and DOUBLE-validate
//      CSRF — once at the proxy and once at the API. That'd be fine
//      semantically but every existing dashboard mutation would break
//      because the API would expect an `x-csrf-token` matching the
//      forwarded cookie, and the dashboard sends a DIFFERENT
//      double-submit token (its own). Don't do that.
//
//   2. Removing the cookie strip — or removing the API's "no cookies =
//      bypass" branch — would silently turn proxy-mediated mutations
//      into 403s. Both halves rely on each other staying as-is.
//
// If a future change requires forwarding cookies (e.g. session-cookie
// pass-through), introduce an `x-internal-proxy: <shared-secret>`
// header that the API trusts to skip its CSRF check entirely, then
// drop the cookie strip + restore the upstream path. Don't piecemeal.
function buildForwardedHeaders(request: NextRequest, accessToken: string | undefined): Headers {
  const out = new Headers();
  request.headers.forEach((value, key) => {
    if (FORWARDABLE_REQUEST_HEADERS.has(key.toLowerCase())) {
      out.set(key, value);
    }
  });
  if (accessToken) {
    out.set('Authorization', `Bearer ${accessToken}`);
  }
  // Always strip cookie regardless — a future allowlist edit cannot reintroduce it.
  out.delete('cookie');
  return out;
}

function reduceUpstreamHeaders(input: Headers): Headers {
  const out = new Headers();
  input.forEach((value, key) => {
    if (FORWARDABLE_RESPONSE_HEADERS.has(key.toLowerCase())) {
      out.set(key, value);
    }
  });
  return out;
}

function originGuardOk(request: NextRequest): boolean {
  // Browser-set hint: same-origin or same-site is fine. Cross-site mutations
  // are rejected. None header (e.g. user-typed URL) is allowed only on GET
  // (caller handles GET vs mutation separately).
  const fetchSite = request.headers.get('sec-fetch-site');
  return fetchSite === 'same-origin' || fetchSite === 'same-site';
}

async function proxyRequest(request: NextRequest, pathParts: string[]) {
  const url = new URL(request.url);
  const targetUrl = buildUpstreamUrl(pathParts, url.search);
  if (!targetUrl) {
    return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
  }

  const method = request.method.toUpperCase();

  // Cross-origin / no-CSRF mutations are blocked. GETs are OK from any origin
  // because the upstream API enforces auth via the Bearer header anyway.
  if (MUTATION_METHODS.has(method)) {
    if (!originGuardOk(request)) {
      return NextResponse.json({ error: 'Cross-origin request rejected' }, { status: 403 });
    }
    if (!csrfTokenOk(request)) {
      return NextResponse.json({ error: 'CSRF token missing or mismatched' }, { status: 403 });
    }
  }

  const accessToken = request.cookies.get(ACCESS_TOKEN_COOKIE)?.value;
  const headers = buildForwardedHeaders(request, accessToken);

  const body =
    method === 'GET' || method === 'HEAD' ? undefined : await request.arrayBuffer();

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);

    const response = await fetch(targetUrl, {
      method,
      headers,
      body,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    return new NextResponse(await response.arrayBuffer(), {
      status: response.status,
      headers: reduceUpstreamHeaders(response.headers),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      return NextResponse.json(
        { error: 'Request timed out', message: 'The backend server took too long to respond.' },
        { status: 504 }
      );
    }
    return NextResponse.json(
      { error: 'Service unavailable', message: 'Unable to connect to the backend server.' },
      { status: 502 }
    );
  }
}

export async function GET(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function POST(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function PUT(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}
