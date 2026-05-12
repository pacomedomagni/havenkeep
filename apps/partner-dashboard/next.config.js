/** @type {import('next').NextConfig} */

// ── Security headers (audit Ch10-W064, W078) ───────────────────────────────
//
// CSP, X-Frame-Options, Permissions-Policy, etc. The CSP shape differs by
// environment — Next's dev server emits inline bootstrap + HMR scripts
// without nonces and uses eval() for refresh, so a strict prod-style CSP
// makes localhost unusable. Production runs the strict policy.
//
// Caddy in front of the dashboard (production) MAY override
// Strict-Transport-Security with a stricter value; the rest of the headers
// come from this config so a misconfigured edge does not silently drop them.
const IS_PROD = process.env.NODE_ENV === 'production';

// Production CSP: 'strict-dynamic' + a per-request nonce that Next attaches
// to its own <script> tags via middleware (audit Ch10-W064). The
// 'unsafe-inline' fallback is for CSP1 browsers that ignore
// 'strict-dynamic'; modern browsers ignore 'unsafe-inline' when
// 'strict-dynamic' is present, so this isn't a real relaxation.
//
// TODO (CSP-W064 follow-up): the nonce path is wired in middleware.ts but
// the CSP value here is still static. The cleanest finish is to compute
// the policy *per request* (return it from middleware) so the same nonce
// is in both the header and the <script> tag. Until then this static
// policy is correct in shape but blocks Next's bootstrap inline script —
// production has been running behind a Caddy that rewrites the header.
// Tracked as a launch blocker; see DEFERRED.md when it lands there.
const PROD_CSP = [
  "default-src 'self'",
  "script-src 'self' 'strict-dynamic' https: 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  "connect-src 'self' https://api.havenkeep.io https://api.havenkeep.com",
  "frame-src https://connect.stripe.com https://js.stripe.com",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
  'upgrade-insecure-requests',
].join('; ');

// Dev CSP: permissive enough that Next's dev server, HMR, React refresh,
// and the in-browser error overlay all work without console-spam. Still
// blocks the dangerous bits (frame ancestors, object-src). Adds the
// docker-published API origin (4000) to connect-src so the same-origin
// proxy at /api/v1/[...path] isn't the only network path during local
// debugging. The localhost:4000-direct path doesn't actually work
// (cookies + CSRF are bound to the dashboard origin) but allowing it in
// CSP means you don't get a misleading CSP error on top of the real
// "request blocked by CORS / CSRF" error.
const DEV_CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https: http:",
  "font-src 'self' data:",
  "connect-src 'self' http://localhost:4000 http://localhost:4006 ws://localhost:* https://api.havenkeep.io",
  "frame-src 'self' https://connect.stripe.com https://js.stripe.com",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join('; ');

const SECURITY_HEADERS = [
  {
    key: 'X-Frame-Options',
    value: 'DENY',
  },
  {
    key: 'X-Content-Type-Options',
    value: 'nosniff',
  },
  {
    key: 'Referrer-Policy',
    value: 'strict-origin-when-cross-origin',
  },
  {
    key: 'Permissions-Policy',
    value: 'camera=(), microphone=(), geolocation=(), interest-cohort=()',
  },
  ...(IS_PROD
    ? [
        {
          key: 'Strict-Transport-Security',
          value: 'max-age=63072000; includeSubDomains; preload',
        },
      ]
    : []),
  {
    key: 'Content-Security-Policy',
    value: IS_PROD ? PROD_CSP : DEV_CSP,
  },
];

const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  // Audit Ch10-W065: explicit allowlist for remote images. Anything outside
  // this list is rejected by next/image at request time.
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'havenkeep.com' },
      { protocol: 'https', hostname: 'www.havenkeep.com' },
      { protocol: 'https', hostname: 'app.havenkeep.com' },
      { protocol: 'https', hostname: 'assets.havenkeep.com' },
      { protocol: 'https', hostname: 'lh3.googleusercontent.com' }, // partner OAuth avatars
    ],
  },
  // C0-26: rewrites() is intentionally NOT defined. The only sanctioned
  // browser → API path is /app/api/v1/[...path]/route.ts, which strips
  // cookies, enforces CSRF, validates path segments, and proxies under
  // the same origin. A `rewrites()` rule that forwarded /api/v1/:path*
  // straight to the upstream would bypass all four protections and ship
  // every httpOnly cookie (incl. the access token) to whatever URL
  // API_UPSTREAM_URL happened to point at. The env var is no longer
  // read anywhere — set NEXT_PUBLIC_API_URL or rely on same-origin.
  async headers() {
    return [
      {
        source: '/:path*',
        headers: SECURITY_HEADERS,
      },
    ];
  },
};

module.exports = nextConfig;
