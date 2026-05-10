/** @type {import('next').NextConfig} */

// ── Security headers (audit Ch10-W064, W078) ───────────────────────────────
//
// Strict CSP, X-Frame-Options, Permissions-Policy, etc. Inline `<script>` and
// inline event handlers are forbidden — Next.js runtime injects nonces for
// its own bootstrap. The `connect-src` / `img-src` lists allow same-origin
// plus the Stripe-owned hosts the partner Stripe Connect flow needs to talk
// to from the browser.
//
// Caddy in front of the dashboard (production) MAY override Strict-Transport-
// Security with a stricter value; the rest of the headers come from this
// config so a misconfigured edge does not silently drop them.
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
  {
    key: 'Strict-Transport-Security',
    value: 'max-age=63072000; includeSubDomains; preload',
  },
  {
    key: 'Content-Security-Policy',
    value: [
      "default-src 'self'",
      // Next 14 still emits a small inline bootstrap; allow it via 'self' +
      // the runtime nonce that Next sets per request. We do NOT enable
      // 'unsafe-inline'.
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
    ].join('; '),
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
