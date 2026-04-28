#!/usr/bin/env bash
# Build + upload signed release artifacts for HavenKeep.
#
# Outputs:
#   apps/mobile/build/ios/ipa/Runner.ipa            (uploaded to TestFlight)
#   apps/mobile/build/app/outputs/bundle/release/app-release.aab  (uploaded to Play Internal Testing)
#
# Usage:
#   scripts/build-release.sh ios           # iOS only (build + TestFlight upload)
#   scripts/build-release.sh android       # Android only (build + Play Internal upload)
#   scripts/build-release.sh all           # both
#
# Skip the upload step (build artifact only):
#   SKIP_ASC_UPLOAD=1 scripts/build-release.sh ios
#   SKIP_PLAY_UPLOAD=1 scripts/build-release.sh android
#
# Requires:
#   - apps/mobile/.env.production filled in (already wired this branch)
#   - Xcode + valid Apple signing certs in keychain (for ios)
#   - apps/mobile/android/app/upload-keystore.jks + key.properties (for android)
#   - ~/.secrets/app-store-connect.env  + ~/.appstoreconnect/private_keys/*.p8 (for ios upload)
#   - ~/.secrets/google-play-service-account.json (for android upload)
#   - fastlane installed (`brew install fastlane` or `gem install fastlane`)

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

PLATFORM="${1:-all}"
case "$PLATFORM" in
  ios|android|all) ;;
  *) echo "✗ usage: $0 {ios|android|all}"; exit 2 ;;
esac

# ─── Sanity-check: confirm Firebase config files are in place ──────────
# Both gitignored — not committed. If they're missing, the binary crashes
# at startup with a "Firebase not initialised" error in production.
IOS_FIREBASE="apps/mobile/ios/Runner/GoogleService-Info.plist"
ANDROID_FIREBASE="apps/mobile/android/app/google-services.json"
for f in "$IOS_FIREBASE" "$ANDROID_FIREBASE"; do
  if [[ ! -f "$f" ]]; then
    echo "✗ Firebase config missing: $f"
    echo "  Download from Firebase Console → Project settings → Your apps."
    exit 1
  fi
done

cd apps/mobile

# ─── iOS ───────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
  echo "→ Building iOS release IPA…"
  flutter build ipa --release
  IPA_PATH="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)"
  if [[ -z "$IPA_PATH" ]]; then
    echo "✗ flutter build ipa produced no .ipa under build/ios/ipa/"
    exit 1
  fi
  echo "✓ IPA at: $IPA_PATH"
  echo ""

  if [[ "${SKIP_ASC_UPLOAD:-0}" == "1" ]]; then
    echo "  Skipping App Store Connect upload (SKIP_ASC_UPLOAD=1)."
    echo "  Manual upload: open -a Transporter and drag the IPA in."
  elif [[ -x "$HOME/bin/upload-ipa.sh" ]]; then
    "$HOME/bin/upload-ipa.sh" "$IPA_PATH"
  else
    echo "  ~/bin/upload-ipa.sh missing — falling back to manual upload."
    echo "  Run: open -a Transporter and drag $IPA_PATH in."
  fi
fi

# ─── Android ───────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
  if [[ ! -f android/key.properties ]]; then
    echo "✗ apps/mobile/android/key.properties missing. Cannot sign release AAB."
    echo "  Set up the upload keystore + key.properties first."
    exit 1
  fi
  echo "→ Building Android release AAB…"
  flutter build appbundle --release
  AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
  if [[ ! -f "$AAB_PATH" ]]; then
    echo "✗ flutter build appbundle produced no AAB at $AAB_PATH"
    exit 1
  fi
  echo "✓ AAB at: apps/mobile/$AAB_PATH"
  echo ""

  if [[ "${SKIP_PLAY_UPLOAD:-0}" == "1" ]]; then
    echo "  Skipping Play Console upload (SKIP_PLAY_UPLOAD=1)."
    echo "  Manual upload via fastlane: cd apps/mobile/android && fastlane internal"
  else
    echo "→ Uploading to Play Console Internal Testing track via fastlane…"
    cd android
    fastlane internal
    cd ..
  fi
fi

echo ""
echo "✓ release build complete"
