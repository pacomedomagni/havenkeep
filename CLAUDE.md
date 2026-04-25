# HavenKeep — Rules for Claude Code

These are the non-negotiable rules you follow when working on this repo. They override any default tendency to scope down, defer, or leave things "for later."

## The five rules

### 1. Never leave tech debt

When you change code, the area you touched leaves cleaner than you found it. That means unused imports get removed, stale `// TODO` / `// FIXME` / `// HACK` markers get resolved or deleted, half-finished abstractions get finished or removed, redundant code gets collapsed. You do not ship "good enough" — you ship done.

### 2. Never implement backfill logic — even if the change is breaking

No migration shims, no compat branches, no "if-old-shape-then" fallbacks, no dual-read/dual-write paths, no feature flags that exist just to keep old behavior alive. When a contract changes, update every caller in the same change. Breaking changes are acceptable; backfill to hide them is not.

### 3. Never leave legacy or dead code — purge it

When code is replaced, the old version is deleted in the same change. Not commented out. Not parked with a `// deprecated`. Not renamed to `_oldFoo`. Gone. Same rule for unreferenced functions, unreachable branches, commented-out blocks, and any code path no caller exercises. If you're not sure something is used, grep first. If nothing references it, delete it.

### 4. ALL means ALL — you do not decide what to defer

You do not unilaterally call work "out of scope," "for a later pass," "follow-up," "nice-to-have," or "optional." If the work is implied by the task, it's part of the task. "Out of scope" is a decision only the user can make.

When you believe something should be deferred, ask the user. Don't assume, don't silently shrink the change, and don't narrate the skip as if it's done.

### 5. Ship with zero errors and zero warnings

The final state of any change is lint-clean, typecheck-clean, and warning-free across every tool that runs on the affected code:

- **Backend (`apps/api`)**: `npx tsc --noEmit` + `npm test`
- **Marketing (`apps/marketing`)**: `npm run build` (Astro)
- **Partner dashboard (`apps/partner-dashboard`)**: `npm run build`
- **Mobile (`apps/mobile`)**: `flutter analyze` + `flutter test` + `flutter build apk --debug`
- **Shared packages (`packages/*`)**: lint + typecheck

If you encounter pre-existing errors or warnings in files you're touching (or adjacent to your work), you fix them. You do not inherit other people's debt and call it clean — you fix it and move on.

"Warnings that were already there" is not an acceptable excuse. If a warning fires in code you're editing, it blocks the change until it's gone.

---

## How to apply these rules

- Before starting a task, enumerate everything it touches — if that enumeration surfaces work that feels "out of scope," ask, don't trim.
- Before finishing, sweep the files you touched: delete unused imports, kill dead branches, resolve TODOs, ensure typecheck/lint/tests/analyzer all pass clean.
- If a rule and a shortcut conflict, the rule wins.
- If a rule and a user instruction conflict, the user instruction wins — but ask them to acknowledge the rule is being overridden.

## Stack (for orientation)

Monorepo, pnpm + npm hybrid (mobile is its own pubspec workspace).

- **`apps/mobile`** — Flutter (Dart SDK `^3.0.0`). Riverpod, Dio (via `api_client`), `sqflite_sqlcipher`, `flutter_dotenv` for env config (NOT dart-defines). Bundle ID `com.flokou.havenkeep` on both iOS and Android.
- **`apps/api`** — Express + Postgres (raw `pg` client, NOT Prisma). JWT auth with refresh tokens. Routes per feature (`src/routes/*`).
- **`apps/marketing`** — Astro static site. Tailwind dark theme. Hosts `/legal/*` and `/delete-account` for store compliance.
- **`apps/partner-dashboard`** — Next.js admin/partner portal.
- **`packages/shared_models`** — Dart models shared between mobile and any other Dart consumer.
- **`packages/api_client`** — Dart wrapper around Dio for talking to the Express API.

## Auth specifics

Three sign-in paths, all terminating at the Express API:

- **Email/password** — `/api/v1/auth/register`, `/login`, `/refresh`.
- **Google Sign-In** — mobile uses the native SDK with `serverClientId` (Web client from Firebase's linked Cloud project) so the idToken's `aud` matches `config.google.clientId` server-side.
- **Apple Sign-In** — iOS uses the native SDK; Android (and any web/desktop client) uses `WebAuthenticationOptions` with an Apple Developer Services ID. The backend `/auth/apple` endpoint accepts both audiences via `config.apple.bundleId` (single) + `config.apple.servicesIds` (comma-sep array).

Per-environment Services IDs follow the convention:
- `com.flokou.havenkeep.signin.staging`
- `com.flokou.havenkeep.signin`

## Mobile signing

- iOS: Xcode auto-signing under your Apple Developer team.
- Android: upload key at `apps/mobile/android/app/upload-keystore.jks` (gitignored) with credentials in `apps/mobile/android/key.properties` (also gitignored). Play App Signing re-signs on Google's end.
- Both `google-services.json` and `GoogleService-Info.plist` are gitignored — each developer downloads the latest from Firebase Console for their environment.
