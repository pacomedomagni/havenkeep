#!/usr/bin/env node
/**
 * Audit Ch10-W075/W076: regenerate the marketing site's OG images.
 *
 * Astro is a static site so we can't render OG cards per-request via an
 * edge runtime — this script is the build-time equivalent. It produces:
 *
 *   public/og-image.png            ← 1200x630 site-wide hero (W075)
 *   public/og/<slug>.png           ← per-page card (W076)
 *
 * Per-page cards are created from the hero SVG with the page tagline
 * substituted in the tagline `<text>`. The page list lives at the bottom
 * of this file — add a new page by adding an entry to PAGES.
 *
 * Run:
 *   node apps/marketing/scripts/build-og-image.cjs
 *
 * Sharp is not a marketing-app dependency; we resolve it via apps/api's
 * node_modules. If sharp isn't installed (fresh clone, no api install) the
 * script logs and exits 0 so a missing PNG can fall through to the SVG.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SVG_PATH = path.join(ROOT, 'public', 'og-image.svg');
const HERO_PNG = path.join(ROOT, 'public', 'og-image.png');
const PER_PAGE_DIR = path.join(ROOT, 'public', 'og');

let sharp;
try {
  sharp = require(path.join(ROOT, '..', 'api', 'node_modules', 'sharp'));
} catch (err) {
  console.warn('[build-og-image] sharp not found at apps/api/node_modules — skipping. SVG fallback in place.');
  process.exit(0);
}

// XML-escape a string for safe injection into the SVG `<text>` body.
function xmlEscape(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

// Substitute the tagline (and optionally a kicker line above it) in the
// hero SVG. Kept narrow — a literal-string substitution against the known
// hero copy means adding a new page only needs a tagline string and won't
// accidentally rewrite a different element.
const HERO_TAGLINE_LITERAL = 'Never lose money on forgotten warranties';
const KICKER_TEMPLATE = (text) =>
  `<text x="100" y="335" font-family="system-ui, sans-serif" font-size="22" font-weight="600" fill="#A78BFA">${xmlEscape(text)}</text>\n  <!-- Tagline -->`;

function svgWithTagline(svgSource, tagline, kicker) {
  // Replace the tagline body. `replace` with a string treats `$&` etc. as
  // patterns, so use a function arg to defeat that.
  let out = svgSource.replace(HERO_TAGLINE_LITERAL, () => xmlEscape(tagline));
  if (kicker) {
    // Inject the kicker `<text>` immediately before the existing tagline
    // comment so document ordering is preserved.
    out = out.replace('<!-- Tagline -->', () => KICKER_TEMPLATE(kicker));
  }
  return out;
}

async function rasterize(svg, outPath) {
  return sharp(Buffer.from(svg), { density: 144 })
    .resize(1200, 630)
    .png({ compressionLevel: 9, quality: 90 })
    .toFile(outPath);
}

// Per-page cards. Slug must match `Astro.url.pathname.replace(/\//g, '-')`
// so the Layout can pick the right asset (see the slug-to-path resolver
// docs in `Layout.astro`).
const PAGES = [
  { slug: 'home',         tagline: 'Never lose money on forgotten warranties' },
  { slug: 'features',     tagline: 'Track warranties, scan receipts, file claims',         kicker: 'Features' },
  { slug: 'pricing',      tagline: 'Free for 5 items. $24/yr for everything.',             kicker: 'Pricing' },
  { slug: 'about',        tagline: 'Built for homeowners who hate losing money',           kicker: 'About' },
  { slug: 'security',     tagline: 'TLS pinning, encryption at rest, no Sentry',           kicker: 'Security' },
  { slug: 'careers',      tagline: 'Help homeowners stop losing $16B/yr',                  kicker: 'Careers' },
  { slug: 'contact',      tagline: 'Get in touch with the HavenKeep team',                 kicker: 'Contact' },
  { slug: 'faq',          tagline: 'Answers about plans, data, and warranty support',     kicker: 'FAQ' },
  { slug: 'roadmap',      tagline: 'What we are building next',                            kicker: 'Roadmap' },
  { slug: 'blog',         tagline: 'Money-saving guides for homeowners',                   kicker: 'Blog' },
  { slug: 'cookies',      tagline: 'How we use cookies on havenkeep.com',                  kicker: 'Cookies' },
  { slug: 'licenses',     tagline: 'Open-source licenses powering HavenKeep',              kicker: 'Licenses' },
  { slug: 'legal-privacy',tagline: 'How we handle your data',                              kicker: 'Privacy Policy' },
  { slug: 'legal-terms',  tagline: 'Terms of service for HavenKeep',                       kicker: 'Terms' },
  { slug: 'legal-delete-account', tagline: 'Delete your HavenKeep account', kicker: 'Account Deletion' },
];

(async () => {
  if (!fs.existsSync(SVG_PATH)) {
    console.error(`[build-og-image] missing ${SVG_PATH}`);
    process.exit(1);
  }
  const heroSvg = fs.readFileSync(SVG_PATH, 'utf8');

  // Hero (W075).
  const hero = await rasterize(heroSvg, HERO_PNG);
  console.log(`[build-og-image] wrote ${HERO_PNG}  (${hero.size} bytes)`);

  // Per-page (W076).
  fs.mkdirSync(PER_PAGE_DIR, { recursive: true });
  for (const page of PAGES) {
    const out = path.join(PER_PAGE_DIR, `${page.slug}.png`);
    const svg = svgWithTagline(heroSvg, page.tagline, page.kicker);
    const r = await rasterize(svg, out);
    console.log(`[build-og-image] wrote ${out}  (${r.size} bytes)`);
  }
})().catch((err) => {
  console.error('[build-og-image] failed:', err.message);
  process.exit(1);
});
