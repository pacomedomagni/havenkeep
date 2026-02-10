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
  build: {
    inlineStylesheets: 'auto',
  },
});
