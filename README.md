# HavenKeep

**Your Warranties. Protected.**

HavenKeep is a warranty tracker mobile app for homeowners. Track every appliance, get reminders before warranties expire, and save money on claims and extended coverage.

## Monorepo Structure

```
havenkeep/
├── apps/
│   ├── mobile/                 # Flutter app (iOS + Android)
│   └── partner-dashboard/      # Next.js web dashboard (realtors/builders)
├── packages/
│   ├── shared_models/          # Dart data models
│   ├── shared_ui/              # Theme, design system, widgets
│   └── supabase_client/        # Supabase client helpers
├── supabase/                   # Database migrations, edge functions, seed data
└── docs/                       # UX spec and documentation
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile App | Flutter + Dart |
| State Management | Riverpod |
| Navigation | go_router |
| Backend | Supabase (Auth, PostgreSQL, Storage, Edge Functions) |
| Local Database | drift (SQLite) |
| OCR | Mindee API |
| Push Notifications | Firebase Cloud Messaging |
| Partner Dashboard | Next.js (planned) |

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x+)
- [Supabase CLI](https://supabase.com/docs/guides/cli) + Docker
- [Node.js](https://nodejs.org/) (18+) + pnpm
- [Melos](https://melos.invertase.dev/) (`dart pub global activate melos`)

### Setup

```bash
# Clone the repo
git clone <repo-url> havenkeep
cd havenkeep

# Install Dart/Flutter dependencies
melos bootstrap

# Start Supabase locally (requires Docker)
cd supabase && npx supabase start

# Run the Flutter app
cd apps/mobile && flutter run
```

## Documentation

- **[UX Specification](docs/havenkeep-ux-spec.md)** — Complete v6 UI/UX spec (2700 lines). Every screen, flow, data model, and interaction.

## Build Phases

1. **Phase 1:** Core mobile app (onboarding, bulk-add, dashboard, items, CRUD)
2. **Phase 2:** Receipt OCR + barcode scanning
3. **Phase 3:** Realtor/builder referral portal
4. **Phase 4:** Affiliate integration (extended warranties, repair referrals)
5. **Phase 5:** Premium subscription + IAP
6. **Phase 6:** Polish, testing, App Store submission
