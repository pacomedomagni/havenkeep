# HavenKeep Admin Dashboard

Complete admin dashboard for managing the HavenKeep platform.

## Features

### ✅ Authentication & Authorization
- **Admin Login**: Secure login with email/password
- **Role Verification**: Middleware checks `is_admin` flag on all routes
- **Session Management**: Supabase Auth with SSR
- **Protected Routes**: Automatic redirect for non-admin users

### ✅ Dashboard Overview
- **Real-time Stats**: Total users, premium users, items, DAU
- **Value Protected**: Aggregate value of all items under warranty
- **Recent Activity**: Latest signups and user activity
- **Quick Metrics**: Signups by period (24h, 7d, 30d)

### ✅ User Management
- **User List**: Paginated table with search and filtering
- **User Details**: Email, plan, items count, total value
- **Search**: Filter by name or email
- **Plan Filter**: Show all, free, or premium users only
- **Actions**:
  - **Suspend User**: Downgrade to free plan
  - **Delete User**: Permanently remove (cascades to all data)

### ✅ Analytics
- **Growth Metrics**: User growth rate, signups trend
- **Engagement**: DAU, WAU, MAU tracking
- **Conversion**: Premium conversion rate
- **Charts**:
  - Daily signups (30 days) - Line chart
  - Daily items created (30 days) - Bar chart
- **Retention**: DAU/MAU ratio
- **Usage**: Avg items per user

### ✅ Settings
- **Account Info**: Email, user ID
- **Notifications**: Email alerts, daily reports, critical alerts

## Tech Stack

- **Next.js 14**: App Router with Server Components
- **TypeScript**: Full type safety
- **Tailwind CSS**: Utility-first styling
- **Supabase**: Database, Auth, RLS
- **Recharts**: Analytics charts
- **Heroicons**: Icon library

## Setup

1. **Install dependencies**:
   ```bash
   cd apps/partner-dashboard
   npm install
   ```

2. **Environment variables** (copy `.env.local.example` to `.env.local`):
   ```bash
   NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key_here
   SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here
   NEXT_PUBLIC_APP_URL=http://localhost:3001
   ```

3. **Run migrations**:
   ```bash
   cd ../../supabase
   supabase db push
   ```

4. **Create admin user** (in Supabase SQL editor):
   ```sql
   -- Create user via Supabase Auth dashboard first, then:
   UPDATE public.users
   SET is_admin = TRUE
   WHERE email = 'your-admin@email.com';
   ```

5. **Run dev server**:
   ```bash
   npm run dev
   ```

6. **Access dashboard**: http://localhost:3001

## Database Views

The dashboard uses these views (created in migration `00002_add_admin_roles.sql`):

- `admin_stats`: Overall platform statistics
- `admin_daily_signups`: Daily signup counts (30 days)
- `admin_daily_items`: Daily items created (30 days)
- `admin_user_activity`: Per-user activity breakdown

## Security

### RLS Policies
All admin queries require `is_admin = TRUE`:
- View all users
- View all items, homes, documents
- Update/delete users

### Middleware
Routes protected by middleware checking:
1. User is authenticated
2. User has `is_admin = TRUE`

Non-admin users redirected to `/unauthorized`.

### API Routes
- `/api/users/suspend` - Downgrade user plan
- `/api/users/delete` - Delete user and all data

Both routes verify admin status server-side.

## File Structure

```
apps/partner-dashboard/
├── src/
│   ├── app/
│   │   ├── (dashboard)/          # Protected dashboard routes
│   │   │   ├── layout.tsx         # Sidebar layout
│   │   │   ├── page.tsx           # Overview dashboard
│   │   │   ├── users/page.tsx     # User management
│   │   │   ├── analytics/page.tsx # Analytics
│   │   │   └── settings/page.tsx  # Settings
│   │   ├── login/page.tsx         # Admin login
│   │   ├── unauthorized/page.tsx  # Access denied
│   │   ├── api/users/             # API routes
│   │   ├── layout.tsx             # Root layout
│   │   └── globals.css            # Global styles
│   ├── components/
│   │   ├── Sidebar.tsx            # Navigation sidebar
│   │   ├── Header.tsx             # Page header
│   │   ├── StatsCard.tsx          # Metric cards
│   │   ├── UserTable.tsx          # User list table
│   │   ├── SignupsChart.tsx       # Signups line chart
│   │   └── ItemsChart.tsx         # Items bar chart
│   └── lib/
│       ├── supabase.ts            # Browser client
│       └── supabase-server.ts     # Server client
├── middleware.ts                   # Auth middleware
├── package.json
├── tsconfig.json
├── tailwind.config.ts
└── next.config.js
```

## Deployment

See main deployment guide: `docs/DEPLOYMENT_GUIDE.md`

**Quick deploy to Vercel**:
```bash
npm run build
npx vercel deploy --prod
```

Add environment variables in Vercel dashboard.

## Admin Dashboard Complete ✅

All features implemented:
- ✅ Admin authentication with role check
- ✅ User management (list, search, suspend, delete)
- ✅ Analytics dashboard with charts
- ✅ Real-time stats and metrics
- ✅ Settings page
- ✅ API routes for user actions
- ✅ RLS policies for admin access
- ✅ Responsive design

**Status**: Production-ready
