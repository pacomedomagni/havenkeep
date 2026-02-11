# 📧 Email Integration Guide - SendGrid

## Overview

HavenKeep uses SendGrid for transactional email delivery. This guide covers setup, configuration, and email templates for the partner gift system.

---

## 🚀 Quick Setup

### 1. Create SendGrid Account

1. Sign up at [sendgrid.com](https://sendgrid.com)
2. Choose the Free plan (40,000 emails/month for first 30 days, then 100 emails/day)
3. Verify your email address

### 2. Create API Key

1. Go to **Settings** → **API Keys**
2. Click **Create API Key**
3. Name: `HavenKeep Production` (or `Development`)
4. Choose **Restricted Access**
5. Grant **Full Access** to:
   - Mail Send
   - Email Activity
6. Copy the API key (you'll only see it once!)

### 3. Verify Sender Identity

**Option A: Single Sender Verification** (Quickest)
1. Go to **Settings** → **Sender Authentication**
2. Click **Verify a Single Sender**
3. Add email: `noreply@havenkeep.com`
4. Fill in form and verify email

**Option B: Domain Authentication** (Recommended for Production)
1. Go to **Settings** → **Sender Authentication**
2. Click **Authenticate Your Domain**
3. Choose your DNS provider
4. Add the provided DNS records to your domain
5. Verify authentication

### 4. Configure Environment Variables

Add to `/apps/api/.env`:

```bash
# SendGrid Configuration
SENDGRID_API_KEY=SG.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SENDGRID_FROM_EMAIL=noreply@havenkeep.com
SENDGRID_REPLY_TO_EMAIL=support@havenkeep.com

# App URLs (for email links)
APP_BASE_URL=https://app.havenkeep.com
DASHBOARD_URL=https://partners.havenkeep.com
API_URL=https://api.havenkeep.com
```

### 5. Test Email Sending

```bash
# Start the API server
cd apps/api
npm run dev

# Test endpoint (create a partner gift)
curl -X POST http://localhost:3000/api/v1/partners/gifts \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "homebuyer_name": "John Doe",
    "homebuyer_email": "john@example.com",
    "premium_months": 6
  }'

# Check SendGrid Activity Feed
# Go to Activity Feed in SendGrid dashboard to see delivery status
```

---

## 📧 Email Templates

### 1. Gift Activation Email

**Sent when:** Partner creates a closing gift

**Template:** [email.service.ts:sendGiftActivationEmail()](../apps/api/src/services/email.service.ts)

**Features:**
- Partner branding (logo, brand color)
- Personalized greeting
- Custom message from partner
- Features overview
- Large CTA button
- Activation code fallback
- Mobile responsive
- Dark mode compatible

**Preview:**
- Hero section with partner branding
- "You've Received a Gift!" headline
- Gift details (X months premium)
- Personal message card
- Feature list with icons
- "Activate Your Gift" button
- Activation code box
- Footer with HavenKeep branding

**Variables:**
- `to` - Homebuyer email
- `homebuyer_name` - Full name (uses first name in greeting)
- `partner_name` - Partner company/name
- `premium_months` - 3, 6, or 12
- `activation_url` - Deep link to activation screen
- `activation_code` - 6-digit code
- `custom_message` - Optional partner message
- `brand_color` - Hex color (default: #3B82F6)
- `logo_url` - Partner logo URL

### 2. Partner Welcome Email

**Sent when:** New partner registers

**Template:** [email.service.ts:sendPartnerWelcomeEmail()](../apps/api/src/services/email.service.ts)

**Features:**
- Welcome message
- Next steps checklist
- CTA to dashboard
- Support contact info

**Variables:**
- `to` - Partner email
- `partner_name` - Full name
- `company_name` - Optional company name

---

## 🎨 Email Design System

### Brand Colors
- **Primary Blue:** `#3B82F6` (default brand color)
- **Success Green:** `#10B981`
- **Warning Yellow:** `#F59E0B`
- **Error Red:** `#EF4444`

### Typography
- **Font Stack:** `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif`
- **Headings:** Bold, 28px (H1), 20px (H2)
- **Body:** Regular, 16px
- **Small:** 14px, 13px, 12px

### Layout
- **Max Width:** 600px
- **Padding:** 40px (desktop), 20px (mobile)
- **Border Radius:** 12px (containers), 8px (cards), 4px (borders)
- **Shadows:** `0 4px 6px rgba(0, 0, 0, 0.1)`

### Responsive Design
- Mobile-optimized (single column)
- Touch-friendly buttons (min 44px height)
- Readable font sizes (min 14px)
- Adequate spacing for tapping

---

## 📊 Monitoring & Analytics

### SendGrid Activity Feed

Monitor email delivery in real-time:

1. Go to **Activity** → **Activity Feed**
2. Filter by:
   - Date range
   - Email address
   - Subject
   - Status (delivered, opened, clicked, bounced)

### Key Metrics to Track

**Delivery Metrics:**
- **Delivery Rate:** Target >99%
- **Bounce Rate:** Target <2%
- **Spam Report Rate:** Target <0.1%

**Engagement Metrics:**
- **Open Rate:** Target >40% (gift emails)
- **Click Rate:** Target >60% (gift emails)
- **Activation Rate:** Target >80%

### Email Event Webhook (Optional)

Configure webhook to track email events:

```typescript
// apps/api/src/routes/webhooks.ts
router.post('/sendgrid', async (req, res) => {
  const events = req.body;

  for (const event of events) {
    if (event.event === 'delivered') {
      // Update gift status to 'sent'
    } else if (event.event === 'open') {
      // Track email opened
    } else if (event.event === 'click') {
      // Track link clicked
    } else if (event.event === 'bounce') {
      // Alert partner about invalid email
    }
  }

  res.status(200).send('OK');
});
```

**Setup in SendGrid:**
1. Go to **Settings** → **Mail Settings** → **Event Webhook**
2. Set HTTP POST URL: `https://api.havenkeep.com/webhooks/sendgrid`
3. Select events to track
4. Save

---

## 🔒 Security Best Practices

### API Key Security

✅ **Do:**
- Store API key in environment variables
- Use restricted access keys (not full access)
- Rotate keys every 90 days
- Use different keys for dev/staging/production
- Monitor API key usage

❌ **Don't:**
- Commit API keys to git
- Share API keys in Slack/email
- Use the same key across environments
- Give full access unless necessary

### Email Authentication

**SPF Record:**
```
v=spf1 include:sendgrid.net ~all
```

**DKIM:**
- Automatically configured via domain authentication
- Verifies email wasn't tampered with

**DMARC:**
```
v=DMARC1; p=quarantine; rua=mailto:dmarc@havenkeep.com
```

### Rate Limiting

SendGrid limits:
- **Free Plan:** 100 emails/day
- **Essentials Plan:** 50,000 emails/month ($15/mo)
- **Pro Plan:** 100,000 emails/month ($90/mo)

Application-side rate limiting:
```typescript
// Limit gift creation to prevent email abuse
const gifts = await getPartnerGiftsToday(partnerId);
if (gifts.length >= 100) {
  throw new Error('Daily gift limit reached. Contact support.');
}
```

---

## 🧪 Testing

### 1. Local Testing with MailTrap

For development, use MailTrap to avoid sending real emails:

```bash
# Install MailTrap
npm install nodemailer

# Update config for development
if (config.env === 'development') {
  // Use MailTrap instead of SendGrid
  transporter = nodemailer.createTransport({
    host: 'smtp.mailtrap.io',
    port: 2525,
    auth: {
      user: process.env.MAILTRAP_USER,
      pass: process.env.MAILTRAP_PASS,
    },
  });
}
```

### 2. SendGrid Sandbox Mode

Test email rendering without sending:

```typescript
// Add sandbox mode to email service
const msg = {
  ...emailData,
  mail_settings: {
    sandbox_mode: {
      enable: config.env === 'test',
    },
  },
};
```

### 3. Test Email Addresses

SendGrid test addresses (always succeed/fail):

```typescript
// These emails will always be delivered
test@sendgrid.com
test+success@sendgrid.com

// These will always bounce
test+bounce@sendgrid.com
test+invalid@sendgrid.com
```

---

## 📈 Scaling Considerations

### For 1,000 Gifts/Month
- **Plan:** Free tier (100/day) is sufficient
- **Cost:** $0

### For 10,000 Gifts/Month
- **Plan:** Essentials ($15/month for 50,000 emails)
- **Cost:** $15/month
- **Features:** Email analytics, dedicated IP option

### For 100,000 Gifts/Month
- **Plan:** Pro ($90/month for 100,000 emails)
- **Cost:** $90/month
- **Features:** Advanced analytics, dedicated IPs, subuser management

### High Volume (1M+ emails/month)
- **Plan:** Custom/Premier
- **Cost:** Contact sales
- **Features:** Dedicated IPs, deliverability consulting, SLA

---

## 🐛 Troubleshooting

### Email Not Received

**Check 1: SendGrid Activity Feed**
- Status: Delivered? Check spam folder
- Status: Bounced? Email address invalid
- Status: Deferred? Temporary issue, will retry
- Status: Dropped? Email on suppression list

**Check 2: Sender Authentication**
- Verify single sender or domain is authenticated
- Check DNS records for domain authentication

**Check 3: Application Logs**
```bash
# Check API logs for email errors
tail -f apps/api/logs/app.log | grep "email"
```

### High Bounce Rate

**Causes:**
- Invalid email addresses
- Typos in email field
- Disposable email services
- Old/inactive accounts

**Solutions:**
- Add email validation on frontend
- Implement email verification before sending gifts
- Clean email list regularly

### Emails Going to Spam

**Causes:**
- Missing sender authentication
- High volume from new domain
- Spammy content/formatting
- No unsubscribe link

**Solutions:**
- Complete domain authentication
- Warm up sending reputation gradually
- Review email content for spam triggers
- Add unsubscribe footer
- Monitor spam complaint rate

### SendGrid API Errors

**Error: 401 Unauthorized**
```
Solution: Check SENDGRID_API_KEY in .env
```

**Error: 403 Forbidden**
```
Solution: API key lacks Mail Send permission
```

**Error: 429 Too Many Requests**
```
Solution: Rate limit exceeded, upgrade plan
```

**Error: 500 Internal Server Error**
```
Solution: Check SendGrid status page, contact support
```

---

## 📝 Email Template Customization

### Partner Branding

Partners can customize:
- **Brand Color:** Used for buttons, accents, borders
- **Logo:** Displayed in email header
- **Message:** Personal note to homebuyer

Example:
```typescript
await EmailService.sendGiftActivationEmail({
  to: 'buyer@example.com',
  homebuyer_name: 'John Doe',
  partner_name: 'ABC Realty',
  brand_color: '#E53E3E', // Red theme
  logo_url: 'https://abcrealty.com/logo.png',
  custom_message: 'Thanks for choosing ABC Realty! Enjoy your new home.',
  // ... other params
});
```

### Dynamic Content

Add conditional sections:
```html
${gift.closing_date ? `
  <p>Congratulations on closing on ${formatDate(gift.closing_date)}!</p>
` : ''}
```

### Localization

Add language support:
```typescript
const locale = gift.locale || 'en';
const translations = {
  en: { subject: 'You've Received a Gift!' },
  es: { subject: '¡Has Recibido un Regalo!' },
};

subject: translations[locale].subject
```

---

## 🎯 Best Practices

### Email Timing
- **Gift Creation:** Send immediately
- **Reminders:** Send 1 week before expiration
- **Follow-ups:** Send 3 days after creation if not activated

### Subject Lines
✅ Good:
- "🎁 John sent you 6 months of HavenKeep Premium"
- "Your closing gift from ABC Realty is ready!"
- "Protect your new home with this gift"

❌ Avoid:
- "URGENT: Activate Now!!!" (spammy)
- "You won!" (misleading)
- ALL CAPS SUBJECTS

### Content Guidelines
- Keep it concise (3-4 paragraphs max)
- Use bullet points for features
- Make CTA button prominent
- Include fallback text version
- Add unsubscribe link in footer

### Accessibility
- Use semantic HTML
- Include alt text for images
- Ensure sufficient color contrast
- Use descriptive link text (not "click here")

---

## 📚 Resources

- **SendGrid Docs:** https://docs.sendgrid.com
- **Email Design Guide:** https://templates.mailchimp.com/design/
- **HTML Email Templates:** https://github.com/leemunroe/responsive-html-email-template
- **Email Testing:** https://www.emailonacid.com
- **Deliverability Guide:** https://sendgrid.com/resource/email-deliverability-guide/

---

## ✅ Deployment Checklist

- [ ] Create SendGrid account
- [ ] Generate API key
- [ ] Verify sender email/domain
- [ ] Add environment variables
- [ ] Test email sending locally
- [ ] Configure webhook (optional)
- [ ] Setup monitoring/alerts
- [ ] Review email templates
- [ ] Test spam score
- [ ] Warm up sending reputation (gradual increase)
- [ ] Monitor delivery rates
- [ ] Document runbook for email issues

---

**Last Updated:** February 11, 2026
**Version:** 1.0.0
