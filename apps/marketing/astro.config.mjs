import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';

export default defineConfig({
  integrations: [tailwind()],
  site: 'https://havenkeep.com',
  output: 'static',
  server: {
    host: true,
    port: 4321,
  },
  // Astro's `astro preview` uses Vite under the hood; Vite rejects unknown
  // Host headers by default. Allow all hosts (behind Caddy which already
  // validates the TLS hostname).
  vite: {
    preview: {
      allowedHosts: true,
    },
  },
  build: {
    inlineStylesheets: 'auto',
  },
});
