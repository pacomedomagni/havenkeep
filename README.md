# HavenKeep

HavenKeep is a home asset and warranty tracker. It pays attention so you don't have to: log an appliance once and we remind you before the warranty expires, surface required maintenance, file claims, and tell you which extended warranties are worth the money.

For *what we are building and why*, see [docs/PRODUCT.md](./docs/PRODUCT.md).
For *how it is wired together*, see [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md).
For *the rules every commit must follow*, see [CLAUDE.md](./CLAUDE.md).

This README covers everything else: getting a local environment running, the test gates, deployment, troubleshooting.

---

## 1. Repository layout

```
havenkeep/
├── apps/
│   ├── api/                    # Express + Postgres backend (apps/api)
│   ├── mobile/                 # Flutter iOS + Android app
│   ├── partner-dashboard/      # Next.js admin/partner portal
│   └── marketing/              # Astro static site (havenkeep.com)
├── packages/
│   ├── api_client/             # Dart HTTP wrapper used by mobile
│   ├── shared_models/          # Dart data models + enums
│   └── shared_ui/              # Dart design system + reusable widgets
├── docs/
│   ├── ARCHITECTURE.md         # how the system is built
│   └── PRODUCT.md              # what the product does and for whom
├── CLAUDE.md                   # session rules + outstanding work
└── README.md                   # this file
```

The repo is a hybrid workspace: pnpm/npm for the JS/TS side, pubspec path-dependencies for the Dart side. The two halves never import each other — the contract between them is the API JSON envelope.

---

## 2. Prerequisites

You need:

- **Node.js 20+** with `npm`.
- **Flutter 3.x** (Dart SDK ^3.0.0). Verify with `flutter doctor`.
- **PostgreSQL 16** running locally (or a cloud Postgres connection string).
- **Redis 7+** for rate limits, the user cache, and webhook idempotency cursors.
- **MinIO** (or any S3-compatible object store) for receipt photos. Optional for backend-only work; required for upload flows.
- **Xcode 15+** if you want to run the iOS app locally.
- **Android Studio + JDK 17** if you want to run the Android app locally.

If you're only doing backend or dashboard work, you can skip Flutter / Xcode / Android Studio.

---

## 3. Local setup — first run

### 3.1 Clone and install

```sh
git clone <repo-url> havenkeep
cd havenkeep

# Backend + dashboard + marketing (JS/TS)
( cd apps/api && npm install )
( cd apps/partner-dashboard && npm install )
( cd apps/marketing && npm install )

# Mobile + Dart packages
( cd apps/mobile && flutter pub get )
( cd packages/api_client && flutter pub get )
( cd packages/shared_models && flutter pub get )
( cd packages/shared_ui && flutter pub get )
```

### 3.2 Bring the whole stack up in Docker

Everything except the mobile app runs in `docker-compose` — Postgres, Redis, MinIO, the API, the partner dashboard, and the marketing site. From the repo root:

```sh
docker compose up -d --build
```

That brings up six containers and publishes them on the **40xx port range** (chosen to avoid clashing with other local stacks on `:3000`/`:5432`/`:9001` etc.):

| Service | Host URL | In-container target |
|---|---|---|
| **API** (`havenkeep-api`) | `http://localhost:4000` | `api:3000` |
| **Postgres** (`havenkeep-postgres`) | `localhost:4001` | `postgres:5432` |
| **Redis** (`havenkeep-redis`) | `localhost:4002` | `redis:6379` |
| **MinIO S3 API** (`havenkeep-minio`) | `http://localhost:4003` | `minio:9000` |
| **MinIO console** | `http://localhost:4004` | `minio:9001` |
| **Partner dashboard** (`havenkeep-partner-dashboard`) | `http://localhost:4005` | `partner-dashboard:3001` |
| **Marketing site** (`havenkeep-marketing`) | `http://localhost:4006` | `marketing:4321` |

The port-remap lives in `docker-compose.override.yml` (gitignored). The base `docker-compose.yml` uses the default ports for everything; the override exists so this repo can run alongside other projects that already squat the defaults on the same machine.

Wait for healthchecks (`docker compose ps` — `havenkeep-postgres / redis / minio` should be `healthy`; `api` is `running` once `/health` returns ok):

```sh
curl http://localhost:4000/health
# → {"status":"ok","timestamp":"...","uptime":...,"environment":"development"}
```

### 3.3 The local env file

The root `.env` is the only env file you need to touch for local. It's checked in with placeholder values for everything that has a real key (OpenAI / OAuth / Firebase / SendGrid all blank); the secrets that *are* set (JWT, refresh token, OAuth encryption, DB / Redis / MinIO passwords) were freshly generated for local-dev only.

Code paths that need an external service no-op gracefully when the key is absent:
- **OpenAI blank** → receipt-scan + email-scanner Vision return 501. Quick-add / manual / barcode all work without it.
- **Google/Apple/Microsoft OAuth blank** → email/password sign-in works; the social buttons hide and the OAuth-only routes return 501.
- **SendGrid blank** → outbound mail logs + no-ops; the in-app inbox + push (if Firebase is set up) still work.
- **Firebase blank** → no system push; the cron still writes `notification_history` rows so the in-app inbox and unread badge are correct.

### 3.4 Run migrations and seed data

The API container does NOT auto-migrate at boot (so a deploy can roll back a bad migration cleanly). Run them once after the stack is up:

```sh
docker compose exec api npm run db:migrate
docker compose exec api npm run db:seed
```

Migrations apply under a Postgres advisory lock so running this twice is a no-op. The seed creates two users (see § 3.5).

### 3.5 Seeded local accounts

After `db:seed` you can log in to the API / dashboard / mobile app with either of these:

| Email | Password | Plan | Notes |
|---|---|---|---|
| `dev@havenkeep.com` | `DevPass1234!` | premium (10y) | Home pre-created with seed items + maintenance — drop into the dashboard with data. |
| `onboarding@havenkeep.com` | `OnboardPass1234!` | free | No home, no items — exercises the first-action / bulk-add walkthrough. |

Quick sanity check:

```sh
curl -s -X POST http://localhost:4000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"dev@havenkeep.com","password":"DevPass1234!"}'
```

### 3.6 Run the mobile app

The mobile app reads env from a bundled file (`flutter_dotenv`); `scripts/prepare-env.sh` selects the flavor:

```sh
cd apps/mobile
bash scripts/prepare-env.sh development
flutter pub get
flutter run                          # picks the connected device / emulator
```

For a specific platform:

```sh
flutter run -d "iPhone 16 Pro"       # iOS simulator (need Xcode)
flutter run -d emulator-5554         # Android emulator
```

`.env.development` already points the app at `http://127.0.0.1:4000` (the docker API's host port). For a **physical device** on your LAN, swap `127.0.0.1` for your laptop's LAN IP — the phone can't see your loopback.

### 3.7 Stop, reset, restart

```sh
docker compose stop                                 # pause everything, keep data
docker compose start                                # resume
docker compose down                                 # stop + remove containers (data persists)
docker compose down -v                              # nuke containers + volumes (fresh DB/MinIO next boot)
docker compose logs -f api                          # tail one service
docker compose exec api npm run db:migrate          # re-apply migrations after pulling new code
docker compose restart api                          # quick API restart (after touching code in dev mode)
```

The `havenkeep-api` container mounts `./apps/api/src` so saving a file triggers `tsx watch` and hot-restarts inside the container — you usually don't need to rebuild the image for code changes.

---

## 4. Daily commands

### 4.1 Backend (`apps/api`)

```sh
npm run dev              # watch mode (tsx watch)
npm run build            # tsc → dist/
npm start                # run dist/

npm test                 # Jest. Needs a running test DB — see § 4.4.
npx tsc --noEmit         # typecheck gate. Must be clean before commit. (No package.json alias by design — `npm run build` already runs tsc, so the explicit form keeps gates obvious.)
npm run db:migrate       # run pending migrations
npm run db:seed          # idempotent reseed of reference tables
```

New migrations are added by hand: create `apps/api/src/db/migrations/<NNN>_<short_name>.sql` with the next free number and put your DDL inside. The runner picks them up automatically.

### 4.2 Partner dashboard (`apps/partner-dashboard`)

```sh
npm run dev              # Next.js dev server on :3001
npm run build            # production build (runs tsc + Next compile)
npx tsc --noEmit         # standalone typecheck (no package.json alias — `npm run build` is the gate)
npm test                 # vitest
```

### 4.3 Marketing site (`apps/marketing`)

```sh
npm run dev              # Astro dev on :4321
npm run build            # output → dist/
npm run preview          # serve dist/ for testing
```

### 4.4 Mobile (`apps/mobile`)

```sh
flutter pub get          # install deps
flutter analyze          # static analysis, must be clean before commit
flutter test             # 444+ tests
flutter run              # debug build to connected device

# Builds
flutter build apk --debug                 # quick sanity check
flutter build apk --release --flavor staging
flutter build appbundle --release --flavor production
flutter build ios --release --flavor production
```

### 4.5 Shared packages

Each Dart package has its own `flutter analyze` and `flutter test`. They run automatically as part of `apps/mobile`'s analyzer + test suite, but you can run them in isolation:

```sh
( cd packages/shared_models && flutter analyze && flutter test )
( cd packages/api_client && flutter analyze && flutter test )
( cd packages/shared_ui && flutter analyze )
```

---

## 5. Test gates (the bar for every PR)

Per CLAUDE.md Rule 5 ("Ship with zero errors and zero warnings"), the final state of any change must be lint-clean, typecheck-clean, and warning-free across every tool that runs on the affected code:

| Surface | Command | Pass threshold |
|---|---|---|
| Backend typecheck | `cd apps/api && npx tsc --noEmit` | clean |
| Backend tests | `cd apps/api && npm test` (see § 4.4 below) | 319+ green |
| Partner dashboard typecheck | `cd apps/partner-dashboard && npx tsc --noEmit` | clean |
| Partner dashboard build | `cd apps/partner-dashboard && npm run build` | clean |
| Marketing build | `cd apps/marketing && npm run build` | clean |
| Mobile analyze | `cd apps/mobile && flutter analyze` | clean |
| Mobile tests | `cd apps/mobile && flutter test` | 444+ green |
| Mobile debug build | `cd apps/mobile && flutter build apk --debug` | clean |
| Dart packages | `( cd packages/shared_models && flutter analyze && flutter test )` etc. | clean |

### 4.4 Running `npm test` against the local DB

The API jest suite truncates the schema between suites, so it refuses to run against any DB whose name doesn't contain `test`. Bootstrap a sibling `havenkeep_test` DB once (DB password from the root `.env`'s `POSTGRES_PASSWORD`):

```sh
docker exec havenkeep-postgres psql -U havenkeep -c "CREATE DATABASE havenkeep_test;"

# Migrate the test DB. The migration runner reads DATABASE_URL.
DATABASE_URL=postgresql://havenkeep:$POSTGRES_PASSWORD@localhost:4001/havenkeep_test \
  npm --prefix apps/api run db:migrate
```

Then every run:

```sh
DB_USER=havenkeep DB_PASSWORD=$POSTGRES_PASSWORD \
  TEST_DB_PORT=4001 TEST_REDIS_URL=$REDIS_URL_HOST \
  npm --prefix apps/api test
```

`TEST_DB_PORT` and `TEST_REDIS_URL` are the harness's hooks for the 40xx ports the override ships with. `$REDIS_URL_HOST` is set in the root `.env` to a redis URL that goes via `localhost:4002` with the host-side password (the container's `REDIS_URL` points at the in-network hostname instead).

If you encounter pre-existing errors or warnings in files you're touching (or adjacent to your work), you fix them. "Warnings that were already there" is not an acceptable excuse.

---

## 6. The mobile app's flavor system

The mobile app supports three build flavors, each with its own `.env` file:

| Flavor | env file | API base URL | Bundle suffix |
|---|---|---|---|
| development | `.env.development` | `http://localhost:4000` (or LAN IP) | `app.havenkeep.mobile.dev` |
| staging | `.env.staging` | `https://api.staging.havenkeep.app` | `app.havenkeep.mobile.staging` |
| production | `.env.production` | `https://api.havenkeep.com` | `app.havenkeep.mobile` |

Always run `./scripts/prepare-env.sh <flavor>` before `flutter run` / `flutter build`. The script copies the right env file to `.env`, which `flutter_dotenv` reads at boot.

`firebase_options.dart` reads `FIREBASE_ANDROID_API_KEY` / `FIREBASE_IOS_API_KEY` from the env file. The `GoogleService-Info.plist` and `google-services.json` files (each developer's environment, not committed) live at `apps/mobile/ios/Runner/` and `apps/mobile/android/app/`.

---

## 7. Auth setup notes

### 7.1 Google Sign-In

The mobile app uses the native Google Sign-In SDK. The backend `/auth/google` endpoint accepts an array of audiences via `config.google.clientId` + `GOOGLE_AUDIENCES` env, so iOS, Android, and the Services ID all map to one user record.

Set up a Google Cloud OAuth 2.0 client of type "Web application" — that's the `serverClientId` the mobile app uses. Then create separate iOS and Android OAuth clients for the native flow.

### 7.2 Apple Sign-In

iOS uses the native Sign In with Apple SDK. Android (and any web/desktop client) uses `WebAuthenticationOptions` with an Apple Developer Services ID.

You need to register a Services ID per environment in Apple Developer portal → Identifiers → Services IDs. The convention:
- `app.havenkeep.mobile.signin.staging` — staging
- `app.havenkeep.mobile.signin` — production

Configure each Services ID with the corresponding redirect URL (`staging.havenkeep.app` or `havenkeep.app`).

### 7.3 Email scanner OAuth

- **Gmail**: standard OAuth 2.0 with `client_id` + `client_secret`. The app uses `flutter_web_auth_2` to capture the code; the API exchanges it server-side. Read-only scope only (`gmail.readonly`).
- **Outlook**: Azure AD app registered as **confidential / web client** (NOT "public client"). The mobile flow does NOT send PKCE — the API holds the secret and Microsoft would reject a half-completed PKCE handshake.

---

## 8. Useful one-offs

### 8.1 Reset the dev database

From the repo root:

```sh
docker compose down -v                                      # nukes the postgres + redis + minio volumes
docker compose up -d postgres redis minio
( cd apps/api && npm run db:migrate && npm run db:seed )    # set DATABASE_URL inline if your port isn't :5432
```

### 8.2 Tail the API logs in pretty form

```sh
cd apps/api
npm run dev | npx pino-pretty -t -i pid,hostname
```

### 8.3 Connect to staging Postgres

```sh
ssh root@206.189.26.12
docker exec -it infra-postgres psql -U havenkeep -d havenkeep
```

### 8.4 Tail staging logs

Browser: `https://logs.staging.kouakoudomagni.com` (Dozzle, basic auth — ask Domagni for credentials).

CLI:

```sh
ssh root@206.189.26.12 'docker logs havenkeep-api -f'
```

### 8.5 Verify the audit hash chain locally

```sh
docker exec -it infra-postgres psql -U havenkeep -d havenkeep \
  -c "SELECT * FROM verify_audit_chain();"
```

Empty result = clean. Any rows = tampering or missed migration.

---

## 9. Deployment

### 9.1 Staging

The deploy system lives at `~/Projects/staging/` (separate repo, not in this monorepo):

```sh
cd ~/Projects/staging
./ship.sh havenkeep            # builds 3 images, scps tarballs, runs migrations, restarts
./rollback.sh havenkeep        # roll back to previous image tag
```

What `ship.sh` does:
1. Builds `havenkeep-api`, `havenkeep-dashboard`, `havenkeep-marketing` for `linux/amd64` on your laptop.
2. Saves each as a gzipped tarball.
3. `scp`s to `/opt/staging/havenkeep/images/`.
4. SSHes and triggers `/opt/staging/havenkeep/deploy.sh <tag>`, which:
   - Runs migrations as a one-shot container (`profile: migrate`).
   - Flips `IMAGE_TAG=` in `.env`.
   - `docker compose up -d --force-recreate`.
   - Healthchecks. Failed healthcheck → automatic rollback to the previous tag.

Per-app routing (Caddy at `/opt/staging/infra/Caddyfile`):

| Surface | URL | Container |
|---|---|---|
| Marketing | `https://staging.havenkeep.app` | `havenkeep-marketing` |
| API | `https://api.staging.havenkeep.app` | `havenkeep-api` |
| Partner dashboard | `https://partner.staging.havenkeep.app` | `havenkeep-dashboard` |

(Subdomain note: staging uses `partner.` singular — that's what the live Caddyfile binds.)

Staging secrets live on the droplet, not in this repo:
- `/opt/staging/havenkeep/.env` — just `IMAGE_TAG=<tag>`, read by compose.
- `/opt/staging/havenkeep/.env.api` — API runtime env: `APP_BASE_URL`, `FRONTEND_URL`, `DASHBOARD_URL`, `CORS_ORIGINS`, `JWT_SECRET`, `REFRESH_TOKEN_SECRET`, `OAUTH_TOKEN_ENCRYPTION_SECRET`, OAuth client IDs/secrets, SendGrid + OpenAI + RevenueCat keys, etc.
- `/opt/staging/havenkeep/.env.dashboard` — Next.js runtime env.
- `/opt/staging/infra/.env` — shared infra (postgres root password, per-app DB passwords, MinIO root + 6 per-app keypairs, Redis password).

### 9.2 Production

There is no production deployment yet. See [CLAUDE.md](./CLAUDE.md) Part 3 for the mobile build-prep checklist.

---

## 10. Troubleshooting

### 10.1 "Migration runner is hanging"

Another process holds the advisory lock. Either another dev is migrating, a previous run crashed mid-flight, or you've got a zombie process. Check:

```sh
docker exec -it infra-postgres psql -U havenkeep -d havenkeep \
  -c "SELECT * FROM pg_locks WHERE locktype = 'advisory';"
```

If a lock has been held for hours, the holder is dead. Clear it:

```sh
docker exec -it infra-postgres psql -U havenkeep -d havenkeep \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction';"
```

### 10.2 "Mobile app says 'Unknown enum value'"

The server is returning an enum value the client doesn't recognise. Check Crashlytics for the `enum_drift: ...` breadcrumb — it includes the enum name, the unknown value, and the fallback. Either the server shipped a new value before the mobile binary did (need a coordinated deploy) or you missed adding a case to the Dart enum (`packages/shared_models/lib/src/enums.dart` or the per-feature enums in `packages/shared_models/lib/src/*.dart`).

### 10.3 "OAuth code redemption returns 'invalid_grant'"

The redirect URI must match between the OAuth client config (Google Cloud / Microsoft Azure / Apple Developer portal) and the value the API sends in the token-exchange POST. The mobile app passes its `redirect_uri` to `/api/v1/email-scanner/scan`; the API replays it verbatim. Mismatch → `invalid_grant`.

### 10.4 "Mobile build fails on `pod install`"

```sh
cd apps/mobile/ios
rm -rf Pods Podfile.lock
pod repo update
pod install
```

If still failing, check that `flutter doctor -v` shows the correct Xcode and that you've accepted the Xcode license: `sudo xcodebuild -license accept`.

### 10.5 "I get 'CORS error' from the dashboard"

The dashboard's browser bundle ships with `NEXT_PUBLIC_API_URL=''` so calls go through the same-origin proxy at `/api/v1/[...path]`. If you've set `NEXT_PUBLIC_API_URL=http://localhost:4000`, the browser will make a cross-origin request and CORS will block it (the API only allows the dashboard's origin, not arbitrary origins). Unset that env var and let the proxy do its job.

### 10.6 "Helmet says my CSP is broken"

Helmet's CSP is locked to `api.revenuecat.com` plus the dashboard's own origin. If you're loading anything from a different origin, you'll see a CSP violation. Don't relax the CSP — bring the dependency on-host or add the specific origin to the allowlist in [`apps/api/src/app.ts`](./apps/api/src/app.ts) (and document it).

---

## 11. Contributing

Read [CLAUDE.md](./CLAUDE.md) before opening a PR. The five rules in Part 1 are non-negotiable:

1. Never leave tech debt.
2. Never implement backfill logic, even on breaking changes.
3. Never leave legacy or dead code — purge it.
4. ALL means ALL — you do not unilaterally defer scope.
5. Ship with zero errors and zero warnings (every gate in §5 of this README must be green).

If a rule and a shortcut conflict, the rule wins. If a rule and a user instruction conflict, the user instruction wins — but the user must acknowledge the rule is being overridden.

---

## 12. License

Proprietary. All rights reserved. Not for redistribution.

---

## 13. Contact

- Engineering / general: `engineering@havenkeep.com`
- Security disclosure: `security@havenkeep.com`
- Privacy / GDPR / CCPA requests: `privacy@havenkeep.com`
