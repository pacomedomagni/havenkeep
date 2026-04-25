# HavenKeep Android — Fastlane

CLI publishing for the HavenKeep Android app. Mirrors the Restorae setup; the same Play service-account JSON works across all apps in the developer account.

## Prereqs (one-time per machine)

- `fastlane` installed (`brew install fastlane`).
- Play service-account JSON at `~/.secrets/google-play-service-account.json` (or `SUPPLY_JSON_KEY` env var pointing elsewhere).
- The Play Console app for `com.flokou.havenkeep` exists and the service account has been granted permission on it (Play Console → Users and permissions → invite the service-account email).

## Lanes

| Lane | What it does |
| --- | --- |
| `fastlane validate` | Sanity-check the service-account JSON without uploading anything. |
| `fastlane internal` | Upload the latest AAB to **Internal Testing** as a draft. Open Play Console UI to click "Start rollout". Required while the app is in draft state (no production release yet). |
| `fastlane alpha` | Promote to **Closed / Alpha** with `release_status: "completed"`. |
| `fastlane production` | Promote to **Production** with `release_status: "completed"`. |

## Typical flow

```sh
cd apps/mobile
flutter build appbundle --release \
  --dart-define=API_BASE_URL=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=... \
  --dart-define=APPLE_SERVICES_ID=... \
  --dart-define=APPLE_REDIRECT_URI=...
cd android
fastlane internal
```

Then in Play Console → **Test and release → Internal testing** → click **Start rollout to Internal testing** on the new draft.

## Why "draft" for internal?

Play's API rejects `release_status: "completed"` on any app still in "draft app" state — meaning no published production release. Internal Testing rollouts don't graduate the app out of draft. Once 1.0 ships to Production, flip the `internal` lane to `release_status: "completed"` for hands-off CLI deploy.
