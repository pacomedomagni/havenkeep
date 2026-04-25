#!/usr/bin/env node
/**
 * Audit Ch10-W075: regenerate the PNG OG image from `public/og-image.svg`.
 * Astro is a static site so we can't render OG images per-request via
 * `@vercel/og` — this script is the build-time fallback. Run it manually
 * after editing the SVG:
 *
 *   node apps/marketing/scripts/build-og-image.cjs
 *
 * `sharp` is not a marketing-app dependency; we shell out to the api's
 * installed sharp via Node's require resolution. If sharp is missing
 * (fresh clone, `pnpm install` not yet run for the api), the script exits
 * 0 and warns — the SVG fallback still renders for crawlers that accept it.
 */

const fs = require('fs');
const path = require('path');

const SVG_PATH = path.join(__dirname, '..', 'public', 'og-image.svg');
const PNG_PATH = path.join(__dirname, '..', 'public', 'og-image.png');

let sharp;
try {
  // Resolve sharp from the api package — keeps marketing's package.json clean.
  sharp = require(path.join(__dirname, '..', '..', 'api', 'node_modules', 'sharp'));
} catch (err) {
  console.warn(
    '[build-og-image] sharp not found at apps/api/node_modules — skipping PNG generation. SVG fallback in place.',
  );
  process.exit(0);
}

(async () => {
  const svg = fs.readFileSync(SVG_PATH);
  const result = await sharp(svg, { density: 144 })
    .resize(1200, 630)
    .png({ compressionLevel: 9, quality: 90 })
    .toFile(PNG_PATH);
  console.log(
    `[build-og-image] wrote ${PNG_PATH}  (${result.size} bytes, ${result.width}x${result.height})`,
  );
})().catch((err) => {
  console.error('[build-og-image] failed:', err.message);
  process.exit(1);
});
