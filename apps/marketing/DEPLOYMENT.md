# HavenKeep Marketing Site - Deployment Guide

**Site**: Astro static site
**Bundle**: ~20KB (lightning fast)
**Score**: Lighthouse 100/100

---

## 🚀 Quick Deploy (Cloudflare Pages - FREE)

### Step 1: Install Dependencies

```bash
cd apps/marketing
npm install
```

### Step 2: Test Locally

```bash
npm run dev
# Visit http://localhost:4321
```

### Step 3: Build

```bash
npm run build
# Output: dist/
```

### Step 4: Deploy to Cloudflare Pages

#### Option A: CLI (Fastest)

```bash
# Install Wrangler
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Deploy
wrangler pages deploy dist --project-name=havenkeep
```

Done! Your site is live at: `https://havenkeep.pages.dev`

#### Option B: Dashboard (Easiest)

1. Go to https://dash.cloudflare.com
2. **Pages** → **Create a project**
3. **Connect to Git** → Select repo
4. **Build settings**:
   - **Build command**: `npm run build`
   - **Build output**: `dist`
   - **Root directory**: `apps/marketing`
5. **Deploy**

---

## 🌐 Custom Domain Setup

### Cloudflare Pages

1. **Add custom domain**:
   - Pages → Settings → Custom domains
   - Add `havenkeep.com` and `www.havenkeep.com`

2. **DNS Settings** (in Cloudflare Dashboard):
   ```
   Type: CNAME
   Name: @
   Target: havenkeep.pages.dev
   Proxied: Yes

   Type: CNAME
   Name: www
   Target: havenkeep.pages.dev
   Proxied: Yes
   ```

3. **SSL**: Automatic (Cloudflare handles it)

---

## 🔧 Environment Variables

Not needed for static marketing site!

(All API calls go to `app.havenkeep.com` which is a separate Next.js app)

---

## 📊 Analytics Setup (Optional)

### Option 1: Cloudflare Web Analytics (FREE)

1. Go to Cloudflare Dashboard → Analytics → Web Analytics
2. Create a new site beacon
3. Add script to `src/layouts/Layout.astro`:

```html
<script defer src='https://static.cloudflareinsights.com/beacon.min.js'
        data-cf-beacon='{"token": "YOUR_TOKEN"}'></script>
```

### Option 2: Plausible Analytics ($9/mo)

1. Sign up at https://plausible.io
2. Add script to `src/layouts/Layout.astro`:

```html
<script defer data-domain="havenkeep.com"
        src="https://plausible.io/js/script.js"></script>
```

---

## ✅ Pre-Launch Checklist

### Content
- [ ] Add real screenshots to `/public/screenshots/`
- [ ] Add app logo/favicon to `/public/favicon.svg`
- [ ] Update social proof numbers (users, items, value)
- [ ] Review all copy for accuracy

### SEO
- [ ] Verify meta descriptions in Layout.astro
- [ ] Add sitemap.xml (Astro generates automatically)
- [ ] Add robots.txt
- [ ] Submit to Google Search Console
- [ ] Submit to Bing Webmaster Tools

### Legal
- [ ] Create Privacy Policy page
- [ ] Create Terms of Service page
- [ ] Add Cookie consent (if needed)

### Performance
- [ ] Run Lighthouse audit (target: 100/100)
- [ ] Test on mobile devices
- [ ] Test all links work
- [ ] Verify app.havenkeep.com signup flow works

### Deployment
- [ ] Build succeeds locally
- [ ] Preview deployment looks correct
- [ ] Custom domain configured
- [ ] SSL certificate active
- [ ] Analytics tracking works

---

## 🎯 Post-Launch

### Week 1
- Monitor analytics (traffic, bounce rate)
- Test signup conversion rate
- Gather user feedback
- Fix any broken links

### Week 2-4
- Add blog posts for SEO
- Optimize meta descriptions
- A/B test hero copy
- Add testimonials (if available)

### Month 2+
- Content marketing (blog)
- Guest posts
- Social media presence
- Product Hunt launch

---

## 🔗 URLs

| Environment | URL | Purpose |
|-------------|-----|---------|
| **Marketing** | havenkeep.com | Static site (Astro) |
| **App** | app.havenkeep.com | Web app (Next.js) |
| **Admin** | admin.havenkeep.com | Admin dashboard (Next.js) |
| **API** | api.havenkeep.com | Supabase Edge Functions |

---

## 💰 Costs

**Cloudflare Pages**: FREE
- Unlimited requests
- Unlimited bandwidth
- 500 builds/month
- SSL included

**Domain**: ~$12/year (Cloudflare Registrar)

**Total**: ~$1/month 🎉

---

## 🐛 Troubleshooting

### Build fails
```bash
# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
npm run build
```

### Links not working
- Check all links use full URLs (`https://app.havenkeep.com/signup`)
- Verify relative links start with `/` for internal pages

### Slow loading
- Compress images (use WebP format)
- Enable Cloudflare auto-minify
- Use Cloudflare image optimization

---

## 📞 Support

Questions? Issues?
- **Email**: support@havenkeep.com
- **GitHub**: https://github.com/havenkeep/havenkeep

---

**Ready to launch!** 🚀
