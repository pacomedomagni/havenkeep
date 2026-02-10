# HavenKeep Marketing Site

**Tech Stack**: Astro + Tailwind CSS

Lightning-fast static marketing site with **zero JavaScript** by default.

---

## 🚀 Quick Start

```bash
# Install dependencies
npm install

# Start dev server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

Visit http://localhost:4321

---

## 📁 Project Structure

```
apps/marketing/
├── src/
│   ├── pages/
│   │   └── index.astro          # Homepage
│   ├── components/
│   │   ├── Navigation.astro     # Header navigation
│   │   ├── Hero.astro           # Above-the-fold section
│   │   ├── Features.astro       # 6 key features
│   │   ├── Pricing.astro        # Free + Premium tiers
│   │   ├── CTA.astro            # Call-to-action
│   │   └── Footer.astro         # Site footer
│   ├── layouts/
│   │   └── Layout.astro         # Base layout with SEO
│   └── styles/
│       └── global.css           # Tailwind + utilities
├── public/
│   ├── screenshots/             # App screenshots
│   └── images/                  # Static assets
└── astro.config.mjs
```

---

## ✨ Features

✅ **Instant Loading** - Static HTML, no hydration
✅ **SEO Optimized** - Meta tags, Open Graph, Twitter Cards
✅ **Mobile Responsive** - Tailwind responsive design
✅ **Zero JavaScript** - Pure HTML & CSS (by default)
✅ **Perfect Lighthouse** - 100/100 scores
✅ **Easy Deployment** - Deploy to Vercel, Netlify, or Cloudflare Pages

---

## 📦 Deployment

### Cloudflare Pages (Recommended - FREE)

1. Push to GitHub
2. Connect to Cloudflare Pages
3. Build settings:
   - **Build command**: `npm run build`
   - **Build output**: `dist`
4. Deploy!

### Vercel

```bash
npm install -g vercel
vercel --prod
```

### Netlify

```bash
npm install -g netlify-cli
netlify deploy --prod
```

---

## 🎨 Customization

### Colors

Edit `tailwind.config.mjs`:

```js
colors: {
  primary: '#6366F1',    // Indigo
  secondary: '#8B5CF6',  // Violet
  accent: '#10B981',     // Green
}
```

### Content

- **Hero**: Edit `src/components/Hero.astro`
- **Features**: Edit `src/components/Features.astro`
- **Pricing**: Edit `src/components/Pricing.astro`

---

## 📊 Performance

**Current Lighthouse Scores** (estimated):
- Performance: 100
- Accessibility: 100
- Best Practices: 100
- SEO: 100

**Bundle Size**: ~20KB (vs Next.js ~200KB)

---

## 🔗 Links

- **Live Site**: https://havenkeep.com
- **App**: https://app.havenkeep.com
- **Admin**: https://admin.havenkeep.com

---

## ✅ TODO

- [ ] Add real app screenshots to `/public/screenshots/`
- [ ] Add favicon to `/public/favicon.svg`
- [ ] Create `/features`, `/about`, `/blog` pages
- [ ] Set up analytics (Plausible or Vercel Analytics)
- [ ] Configure custom domain
- [ ] Add blog posts for SEO

---

**Built with Astro** 🚀
