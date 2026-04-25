import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import sitemap from '@astrojs/sitemap';

// Audit Ch10-W078, W111: security headers MUST be set on the edge — Astro's
// static output cannot send response headers itself. Production deployment
// (Caddy) is responsible for the actual `Content-Security-Policy`,
// `Strict-Transport-Security`, `X-Frame-Options`, `Permissions-Policy`,
// and `Referrer-Policy` values. The recommended Caddy block is documented
// in `docs/deploy.md` (companion change in this audit phase). The CSP MUST
// at minimum forbid `frame-ancestors`, restrict `script-src` to 'self', and
// allow `connect-src` to api.havenkeep.io / api.havenkeep.com only.
//
// Audit Ch10-W100: `vite.preview.allowedHosts: true` was removed. Behind
// Caddy the upstream Vite preview should refuse unknown Host headers.
export default defineConfig({
  integrations: [
    tailwind(),
    // Audit Ch10-W102: emits /sitemap-index.xml + /sitemap-0.xml at build.
    sitemap(),
  ],
  site: 'https://havenkeep.com',
  output: 'static',
  server: {
    host: true,
    port: 4321,
  },
  vite: {
    preview: {
      allowedHosts: ['havenkeep.com', 'www.havenkeep.com', 'havenkeep.kouakoudomagni.com'],
    },
  },
  build: {
    inlineStylesheets: 'auto',
  },
});
