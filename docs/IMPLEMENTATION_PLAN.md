# HavenKeep - Full Production Implementation Plan

## Current State Analysis

### ✅ What We Have
- **API (Express + PostgreSQL)**
  - Auth system (JWT + refresh tokens, Google OAuth)
  - Users, Homes, Items, Documents CRUD
  - Barcode lookup integration
  - File storage (DigitalOcean Spaces/MinIO)
  - Security (Helmet, CORS, Rate limiting, CSRF)
  - Logging (Pino)

- **Mobile App (Flutter)**
  - Offline-first architecture (Drift/SQLite)
  - Auth flow
  - Items management
  - Document uploads
  - Notifications provider
  - Premium subscription provider

- **Partner Dashboard (Next.js 14)**
  - Basic dashboard structure
  - Partner analytics views

### ❌ What We Need to Build

#### Phase 1: Core Value Features (Weeks 1-3)
1. **Email Receipt Scanner**
   - Gmail/Outlook OAuth integration
   - AI-powered receipt extraction
   - Batch import UI

2. **Instant Value Dashboard**
   - Total value calculations
   - Health score system
   - "You're already winning" UI

3. **Warranty Claim Tracker**
   - Claim logging and tracking
   - ROI calculations
   - Savings feed

#### Phase 2: Engagement Features (Weeks 4-6)
4. **Smart Notifications System**
   - Actionable notification templates
   - Multi-stage warranty reminders
   - Push notification actions

5. **Preventive Maintenance System**
   - Maintenance schedules database
   - Reminder engine
   - Maintenance logging

6. **Insurance Home Inventory**
   - Professional PDF report generation
   - Insurance value calculations
   - Email sharing

#### Phase 3: Revenue Features (Weeks 7-9)
7. **Realtor White-Label Gifting Platform**
   - Gift creation and management
   - Co-branded mobile experience
   - Quarterly reporting
   - Realtor dashboard enhancements

8. **Extended Warranty Marketplace**
   - Provider integrations (Asurion, etc.)
   - Quote comparison UI
   - Purchase flow
   - Commission tracking

9. **Partner Program Enhancements**
   - Advanced analytics
   - Referral tracking
   - Commission payouts

#### Phase 4: Polish & Production (Weeks 10-12)
10. **UX Enhancements**
    - Optimistic UI patterns
    - Micro-interactions and animations
    - Haptic feedback
    - Loading states

11. **Production Readiness**
    - Comprehensive error handling
    - Analytics tracking
    - Performance optimization
    - Security audit
    - Load testing
    - Documentation

---

## Database Schema Extensions

### New Tables

```sql
-- Warranty claims tracking
CREATE TABLE warranty_claims (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  claim_date DATE NOT NULL DEFAULT CURRENT_DATE,
  issue_description TEXT,
  repair_cost DECIMAL(10, 2),
  amount_saved DECIMAL(10, 2),
  status VARCHAR(50) DEFAULT 'completed',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Maintenance schedules and history
CREATE TABLE maintenance_schedules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category item_category NOT NULL,
  task_name VARCHAR(255) NOT NULL,
  description TEXT,
  frequency_months INTEGER NOT NULL,
  estimated_duration_minutes INTEGER,
  prevents_cost DECIMAL(10, 2),
  how_to_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE maintenance_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  schedule_id UUID REFERENCES maintenance_schedules(id) ON DELETE SET NULL,
  task_name VARCHAR(255) NOT NULL,
  completed_date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Email scan history
CREATE TABLE email_scans (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(50) NOT NULL, -- 'gmail', 'outlook'
  scan_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  emails_scanned INTEGER DEFAULT 0,
  receipts_found INTEGER DEFAULT 0,
  items_imported INTEGER DEFAULT 0,
  status VARCHAR(50) DEFAULT 'completed',
  error_message TEXT
);

-- Partner/Realtor program
CREATE TABLE partners (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  partner_type VARCHAR(50) NOT NULL DEFAULT 'realtor', -- 'realtor', 'builder', 'other'
  company_name VARCHAR(255),
  phone VARCHAR(50),
  brand_color VARCHAR(7), -- hex color
  logo_url TEXT,
  subscription_tier VARCHAR(50) DEFAULT 'basic', -- 'basic', 'premium', 'platinum'
  default_message TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE partner_gifts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  homebuyer_email VARCHAR(255) NOT NULL,
  homebuyer_name VARCHAR(255) NOT NULL,
  home_address TEXT,
  closing_date DATE,
  premium_months INTEGER NOT NULL DEFAULT 6,
  custom_message TEXT,
  is_activated BOOLEAN DEFAULT FALSE,
  activated_at TIMESTAMPTZ,
  activated_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  amount_charged DECIMAL(10, 2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE partner_commissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL, -- 'gift', 'warranty_sale', 'referral'
  amount DECIMAL(10, 2) NOT NULL,
  status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'paid', 'cancelled'
  reference_id UUID, -- gift_id or warranty_purchase_id
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Extended warranty purchases
CREATE TABLE warranty_purchases (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(100) NOT NULL,
  plan_name VARCHAR(255) NOT NULL,
  duration_months INTEGER NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  commission DECIMAL(10, 2),
  purchase_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  starts_at DATE NOT NULL,
  expires_at DATE NOT NULL,
  external_policy_id VARCHAR(255),
  status VARCHAR(50) DEFAULT 'active'
);

-- User analytics tracking
CREATE TABLE user_analytics (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Engagement metrics
  last_active_at TIMESTAMPTZ,
  total_app_opens INTEGER DEFAULT 0,
  total_sessions INTEGER DEFAULT 0,

  -- Health score
  current_health_score INTEGER DEFAULT 0,

  -- Savings tracking
  total_warranty_savings DECIMAL(10, 2) DEFAULT 0,
  total_claims_filed INTEGER DEFAULT 0,
  total_maintenance_completed INTEGER DEFAULT 0,

  -- Feature usage
  email_scans_completed INTEGER DEFAULT 0,
  items_added_manually INTEGER DEFAULT 0,
  items_added_via_email INTEGER DEFAULT 0,
  items_added_via_barcode INTEGER DEFAULT 0,

  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Notification templates and history
CREATE TABLE notification_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL UNIQUE,
  type VARCHAR(50) NOT NULL, -- 'warranty_expiring', 'maintenance_due', 'claim_opportunity'
  title_template TEXT NOT NULL,
  body_template TEXT NOT NULL,
  actions JSONB, -- Array of action objects
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE notification_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  template_id UUID REFERENCES notification_templates(id) ON DELETE SET NULL,
  item_id UUID REFERENCES items(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  opened_at TIMESTAMPTZ,
  action_taken VARCHAR(100)
);

-- Savings feed for social proof
CREATE TABLE savings_feed (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_city VARCHAR(100), -- Anonymized location
  amount_saved DECIMAL(10, 2) NOT NULL,
  item_category item_category,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Indexes

```sql
CREATE INDEX idx_warranty_claims_user_id ON warranty_claims(user_id);
CREATE INDEX idx_warranty_claims_item_id ON warranty_claims(item_id);
CREATE INDEX idx_maintenance_history_user_id ON maintenance_history(user_id);
CREATE INDEX idx_maintenance_history_item_id ON maintenance_history(item_id);
CREATE INDEX idx_email_scans_user_id ON email_scans(user_id);
CREATE INDEX idx_partners_user_id ON partners(user_id);
CREATE INDEX idx_partner_gifts_partner_id ON partner_gifts(partner_id);
CREATE INDEX idx_partner_gifts_email ON partner_gifts(homebuyer_email);
CREATE INDEX idx_partner_gifts_activated_user ON partner_gifts(activated_user_id);
CREATE INDEX idx_partner_commissions_partner_id ON partner_commissions(partner_id);
CREATE INDEX idx_warranty_purchases_user_id ON warranty_purchases(user_id);
CREATE INDEX idx_warranty_purchases_item_id ON warranty_purchases(item_id);
CREATE INDEX idx_user_analytics_user_id ON user_analytics(user_id);
CREATE INDEX idx_notification_history_user_id ON notification_history(user_id);
CREATE INDEX idx_savings_feed_created_at ON savings_feed(created_at DESC);
```

### Triggers

```sql
CREATE TRIGGER update_warranty_claims_updated_at BEFORE UPDATE ON warranty_claims
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partners_updated_at BEFORE UPDATE ON partners
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partner_gifts_updated_at BEFORE UPDATE ON partner_gifts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_analytics_updated_at BEFORE UPDATE ON user_analytics
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

---

## API Endpoints to Build

### Email Scanning
- `POST /api/v1/email/auth/gmail` - Initiate Gmail OAuth
- `POST /api/v1/email/auth/outlook` - Initiate Outlook OAuth
- `POST /api/v1/email/scan` - Scan user's email for receipts
- `GET /api/v1/email/scans/:id` - Get scan status
- `GET /api/v1/email/scans` - List user's email scans

### Warranty Claims
- `POST /api/v1/warranty-claims` - Log a warranty claim
- `GET /api/v1/warranty-claims` - List user's claims
- `GET /api/v1/warranty-claims/:id` - Get claim details
- `PUT /api/v1/warranty-claims/:id` - Update claim
- `DELETE /api/v1/warranty-claims/:id` - Delete claim

### Maintenance
- `GET /api/v1/maintenance/schedules` - Get schedules by category
- `POST /api/v1/maintenance/history` - Log completed maintenance
- `GET /api/v1/maintenance/history` - Get maintenance history
- `GET /api/v1/maintenance/due` - Get upcoming maintenance tasks

### Analytics & Stats
- `GET /api/v1/stats/dashboard` - Get dashboard stats
- `GET /api/v1/stats/health-score` - Calculate health score
- `GET /api/v1/stats/savings` - Get total savings
- `GET /api/v1/stats/savings-feed` - Get public savings feed

### Partners
- `POST /api/v1/partners` - Register as partner
- `GET /api/v1/partners/me` - Get partner profile
- `PUT /api/v1/partners/me` - Update partner profile
- `POST /api/v1/partners/gifts` - Create closing gift
- `GET /api/v1/partners/gifts` - List gifts
- `GET /api/v1/partners/gifts/:id` - Get gift details
- `GET /api/v1/partners/commissions` - Get commissions
- `GET /api/v1/partners/analytics` - Get partner analytics

### Extended Warranties
- `POST /api/v1/warranties/quotes` - Get warranty quotes for item
- `POST /api/v1/warranties/purchase` - Purchase extended warranty
- `GET /api/v1/warranties/purchases` - List user's warranty purchases

### Notifications
- `GET /api/v1/notifications` - Get user notifications
- `PUT /api/v1/notifications/:id/read` - Mark as read
- `POST /api/v1/notifications/:id/action` - Log action taken
- `GET /api/v1/notifications/settings` - Get notification preferences
- `PUT /api/v1/notifications/settings` - Update preferences

---

## Mobile App Features to Build

### New Screens
1. Email Scanner Flow
   - OAuth connection screen
   - Scanning progress screen
   - Review and import screen

2. Enhanced Dashboard
   - Value metrics cards
   - Health score widget
   - Needs attention section
   - Quick actions grid

3. Warranty Claims
   - Claim form
   - Claims history
   - Savings tracker

4. Maintenance
   - Maintenance schedule
   - Task completion
   - Maintenance history

5. Extended Warranty
   - Quote comparison
   - Purchase flow
   - Active warranties list

6. Insurance Report
   - Report preview
   - PDF generation
   - Sharing options

### New Providers
- `EmailScanProvider` - Manage email scanning state
- `WarrantyClaimsProvider` - Claims management
- `MaintenanceProvider` - Maintenance tracking
- `StatsProvider` - Dashboard statistics
- `WarrantyMarketplaceProvider` - Extended warranties

---

## Partner Dashboard Enhancements

### New Pages
1. Gift Management
   - Create new gift form
   - Gift list with filters
   - Gift details and analytics

2. Commissions
   - Commission history
   - Payout requests
   - Transaction details

3. Analytics Dashboard
   - User engagement metrics
   - Gift activation rates
   - ROI calculations

4. Settings
   - Branding customization
   - Default messages
   - Subscription tier management

---

## Third-Party Integrations

### Email Providers
- **Google Gmail API**
  - OAuth 2.0 implementation
  - Email search and retrieval
  - Rate limiting handling

- **Microsoft Outlook API**
  - OAuth 2.0 implementation
  - Graph API integration
  - Email parsing

### AI/ML for Receipt Extraction
- **OpenAI GPT-4** or **Anthropic Claude**
  - Receipt data extraction
  - Structured JSON output
  - Fallback and error handling

### Extended Warranty Providers
- **Asurion Home+**
  - API integration (if available)
  - Quote generation
  - Purchase webhook

- **Choice Home Warranty** (Manual/iframe if no API)
- **American Home Shield** (Manual/iframe if no API)

### Payment Processing
- **Stripe** (already integrated)
  - Partner billing
  - Commission payouts via Stripe Connect
  - Warranty purchase processing

---

## Environment Variables Needed

```env
# Email OAuth
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=

MICROSOFT_CLIENT_ID=
MICROSOFT_CLIENT_SECRET=
MICROSOFT_REDIRECT_URI=

# AI APIs
OPENAI_API_KEY=
ANTHROPIC_API_KEY=

# Warranty Providers
ASURION_API_KEY=
ASURION_API_SECRET=

# Stripe Connect (for partner payouts)
STRIPE_CONNECT_CLIENT_ID=
```

---

## Implementation Order

### Week 1-2: Database & Core Backend
- [ ] Create database migration for new tables
- [ ] Build warranty claims API
- [ ] Build maintenance API
- [ ] Build stats/analytics API
- [ ] Set up email OAuth (Gmail + Outlook)
- [ ] Build email scanning worker

### Week 3-4: Mobile Core Features
- [ ] Email scanner UI
- [ ] Enhanced dashboard with stats
- [ ] Warranty claims UI
- [ ] Maintenance UI
- [ ] Health score widget

### Week 5-6: Revenue Features Backend
- [ ] Partners API (registration, profile)
- [ ] Gifts API (create, manage, activate)
- [ ] Commissions tracking
- [ ] Extended warranty quotes API
- [ ] Warranty purchase flow

### Week 7-8: Partner Dashboard
- [ ] Gift management UI
- [ ] Commission tracking UI
- [ ] Enhanced analytics
- [ ] Branding customization

### Week 9-10: Mobile Revenue Features
- [ ] Extended warranty marketplace UI
- [ ] Insurance report generator
- [ ] Realtor gift activation flow

### Week 11: Polish & Optimization
- [ ] Optimistic UI patterns
- [ ] Micro-interactions
- [ ] Performance optimization
- [ ] Error handling improvements

### Week 12: Production Readiness
- [ ] Security audit
- [ ] Load testing
- [ ] Documentation
- [ ] Deployment automation
- [ ] Monitoring and alerting

---

## Testing Strategy

### Unit Tests
- All API endpoints
- Service layer logic
- Database queries
- Providers and repositories (mobile)

### Integration Tests
- Email scanning flow
- Warranty purchase flow
- Partner gift flow
- Payment processing

### E2E Tests
- Critical user flows
- Partner onboarding
- Mobile app key paths

### Load Testing
- API endpoint performance
- Database query optimization
- Email scanning at scale

---

## Deployment Strategy

### Staging Environment
- Test all features before production
- Partner beta testing
- Performance validation

### Production Rollout
1. Database migrations (zero downtime)
2. API deployment (rolling update)
3. Mobile app release (staged rollout)
4. Partner dashboard deployment
5. Marketing site updates

### Monitoring
- API response times
- Error rates
- User engagement metrics
- Revenue metrics
- Partner activation rates

---

## Success Metrics

### Product Metrics
- Email scan completion rate > 70%
- Health score engagement > 50% weekly
- Warranty claim tracking > 40% of claims
- Extended warranty conversion > 5%

### Business Metrics
- Partner signups: 100+ in 3 months
- Partner gift activation rate > 60%
- Premium conversion: 15% → 30%
- Revenue growth: 10x in 6 months

### Technical Metrics
- API p95 latency < 500ms
- Mobile app crash rate < 1%
- Uptime > 99.9%
- Database query time p95 < 100ms

---

**Status:** Ready to implement
**Start Date:** 2026-02-11
**Target Completion:** 2026-05-11 (12 weeks)
