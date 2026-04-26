#!/usr/bin/env bash
#
# capture-store-screenshots.sh — fully automated App Store + Play Console
# screenshot capture for HavenKeep mobile.
#
# How it works:
#   - Launches the app via the dedicated `lib/main_screenshot.dart`
#     entry point. That entry boots the real app, programmatically
#     signs in as the dev user, then walks through a curated list of
#     routes printing `[SCREENSHOT_READY] <name>` between each.
#   - This script tails the flutter-run log; whenever it sees a READY
#     marker it runs `xcrun simctl io <udid> screenshot …` (iOS) or
#     `adb exec-out screencap -p` (Android) and saves the PNG.
#   - When `[SCREENSHOT_DONE]` appears, the run terminates.
#
# Output layout:
#   apps/mobile/store-assets/screenshots/<platform>/<device>/NN-<screen>.png
#
# Required device sizes (Apple/Google submission rules, 2025):
#   iOS:      iPhone 16 Pro Max (1320×2868), iPad Pro 13" M4 (2064×2752)
#   Android:  Pixel 9 phone (1080×2424+)
#
# Usage:
#   ./scripts/capture-store-screenshots.sh --platform ios
#   ./scripts/capture-store-screenshots.sh --platform android
#   ./scripts/capture-store-screenshots.sh --platform ios --device "iPhone 17 Pro Max"

set -euo pipefail

PLATFORM=""
DEVICE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --platform)   PLATFORM="$2"; shift 2 ;;
    --device)     DEVICE_OVERRIDE="$2"; shift 2 ;;
    -h|--help)    sed -n '2,/^set/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)            echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$PLATFORM" != "ios" && "$PLATFORM" != "android" ]]; then
  echo "Usage: $0 --platform ios|android [--device <name>]" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOBILE_DIR="$REPO_ROOT/apps/mobile"
OUT_BASE="$MOBILE_DIR/store-assets/screenshots/$PLATFORM"
mkdir -p "$OUT_BASE"

IOS_DEVICES=(
  "iPhone 16 Pro Max"
  "iPad Pro 13-inch (M4)"
)
ANDROID_DEVICES=(
  "Pixel_9_API_35"
)

green()  { printf "\033[32m%s\033[0m" "$1"; }
yellow() { printf "\033[33m%s\033[0m" "$1"; }
red()    { printf "\033[31m%s\033[0m" "$1"; }
cyan()   { printf "\033[36m%s\033[0m" "$1"; }

slugify() { echo "$1" | tr '[:upper:] ' '[:lower:]_' | tr -d '"()' | tr -s '_'; }

require_running_api() {
  if ! curl -fsS http://localhost:3000/health >/dev/null 2>&1; then
    echo "$(red "✗") API not reachable at http://localhost:3000"
    echo "  Start the stack first:  docker compose up -d"
    exit 1
  fi
}

# ── iOS run ────────────────────────────────────────────────────────────
ios_capture() {
  local device="$1"
  local out_dir="$OUT_BASE/$(slugify "$device")"
  mkdir -p "$out_dir"
  rm -f "$out_dir"/*.png 2>/dev/null

  echo
  echo "$(cyan "── iOS · $device ─────────────────────────────────────────────")"

  local udid
  # Match the line for this exact device, then extract the first UUID
  # in it. Devices like "iPad Pro 13-inch (M4)" embed parens in their
  # name, so a paren-based field split would pick up "M4" instead of
  # the real UUID.
  udid=$(xcrun simctl list devices available \
    | grep -F "    ${device} (" \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1)
  if [[ -z "$udid" ]]; then
    echo "$(red "✗") Simulator '$device' not found."
    echo "    List options:  xcrun simctl list devices available"
    return 1
  fi

  if ! xcrun simctl list devices | grep -q "$udid.*Booted"; then
    echo "  Booting $device …"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    open -a Simulator
    sleep 8
  fi

  local log_file
  log_file=$(mktemp)
  echo "  Launching app via main_screenshot.dart …"
  (
    cd "$MOBILE_DIR"
    # iOS Simulator only supports --debug (release/profile both reject
    # with "not supported by iPhone …"). Debug builds DO paint the
    # "BOTTOM OVERFLOWED" overlay if any RenderFlex actually overflows,
    # but we fixed the bottom-nav overflow upstream so this is clean.
    # The "DEBUG" badge in the corner is also debug-only — for fully
    # polished store screenshots, build for a real device + capture
    # via TestFlight, or post-process to crop the badge.
    flutter run \
      --debug \
      -t lib/main_screenshot.dart \
      -d "$device" \
      --dart-define=ENV=development \
      > "$log_file" 2>&1 &
    echo $! > "$log_file.pid"
  )

  local pid
  pid=$(cat "$log_file.pid")

  # Stream the log; on every [SCREENSHOT_READY] capture; stop on DONE.
  local timeout_at=$(( $(date +%s) + 600 ))
  while [[ $(date +%s) -lt $timeout_at ]]; do
    if [[ -f "$log_file" ]]; then
      while IFS= read -r line; do
        if [[ "$line" == *"[SCREENSHOT_READY] "* ]]; then
          # Bash glob `[CHARS]` is a character class, so we can't use
          # ${line##*[SCREENSHOT_READY] } — it strips through any of
          # those letters. Use sed with a literal-string match instead.
          local name
          name=$(echo "$line" | sed -n 's/.*\[SCREENSHOT_READY\] \([^ ]*\).*/\1/p')
          local out_file="$out_dir/${name}.png"
          if xcrun simctl io "$udid" screenshot "$out_file" >/dev/null 2>&1; then
            echo "  $(green "📸") $out_file"
          else
            echo "  $(red "✗") capture failed for $name"
          fi
        elif [[ "$line" == *"[SCREENSHOT_DONE]"* ]]; then
          echo "  $(green "✓") walk complete"
          # Politely terminate flutter run.
          kill "$pid" 2>/dev/null || true
          break 2
        elif [[ "$line" == *"[SCREENSHOT_PHASE]"* ]]; then
          # Same character-class trap as above.
          local phase
          phase=$(echo "$line" | sed -n 's/.*\[SCREENSHOT_PHASE\] \(.*\)/\1/p')
          echo "    $phase"
        fi
      done < <(tail -n +1 -F "$log_file" 2>/dev/null)
    fi
    sleep 1
  done

  # Cleanup
  kill "$pid" 2>/dev/null || true
  rm -f "$log_file" "$log_file.pid"

  echo
  echo "  output: $out_dir"
  ls -1 "$out_dir" 2>/dev/null | sed 's/^/    /'
}

# ── Android run ────────────────────────────────────────────────────────
android_capture() {
  local emu_name="$1"
  local out_dir="$OUT_BASE/$(slugify "$emu_name")"
  mkdir -p "$out_dir"
  rm -f "$out_dir"/*.png 2>/dev/null

  echo
  echo "$(cyan "── Android · $emu_name ───────────────────────────────────────")"

  local serial
  serial=$(adb devices | awk '/emulator-/ {print $1; exit}')
  if [[ -z "$serial" ]]; then
    echo "$(red "✗") No Android emulator running."
    echo "    Boot one in Android Studio (preferably matching '$emu_name'),"
    echo "    or run:  emulator -avd $emu_name &"
    return 1
  fi

  echo "  Using emulator: $serial"

  local log_file
  log_file=$(mktemp)
  echo "  Launching app via main_screenshot.dart …"
  (
    cd "$MOBILE_DIR"
    # Android emulator's `localhost` is the emulator itself, not the host
    # — the host's loopback is reachable via 10.0.2.2 (Google's standard
    # alias for QEMU's host bridge). Override API_BASE_URL via dart-define
    # so the in-app Dio client points at our docker stack.
    flutter run \
      --debug \
      -t lib/main_screenshot.dart \
      -d "$serial" \
      --dart-define=ENV=development \
      --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
      > "$log_file" 2>&1 &
    echo $! > "$log_file.pid"
  )

  local pid
  pid=$(cat "$log_file.pid")

  local timeout_at=$(( $(date +%s) + 600 ))
  while [[ $(date +%s) -lt $timeout_at ]]; do
    if [[ -f "$log_file" ]]; then
      while IFS= read -r line; do
        if [[ "$line" == *"[SCREENSHOT_READY] "* ]]; then
          # Same character-class trap as the iOS branch — bash glob
          # `[CHARS]` is a class. Use sed for a literal-string match.
          local name
          name=$(echo "$line" | sed -n 's/.*\[SCREENSHOT_READY\] \([^ ]*\).*/\1/p')
          local out_file="$out_dir/${name}.png"
          if adb -s "$serial" exec-out screencap -p > "$out_file" 2>/dev/null && [[ -s "$out_file" ]]; then
            echo "  $(green "📸") $out_file"
          else
            rm -f "$out_file"
            echo "  $(red "✗") capture failed for $name"
          fi
        elif [[ "$line" == *"[SCREENSHOT_DONE]"* ]]; then
          echo "  $(green "✓") walk complete"
          kill "$pid" 2>/dev/null || true
          break 2
        elif [[ "$line" == *"[SCREENSHOT_PHASE]"* ]]; then
          # Same character-class trap as above.
          local phase
          phase=$(echo "$line" | sed -n 's/.*\[SCREENSHOT_PHASE\] \(.*\)/\1/p')
          echo "    $phase"
        fi
      done < <(tail -n +1 -F "$log_file" 2>/dev/null)
    fi
    sleep 1
  done

  kill "$pid" 2>/dev/null || true
  rm -f "$log_file" "$log_file.pid"

  echo
  echo "  output: $out_dir"
  ls -1 "$out_dir" 2>/dev/null | sed 's/^/    /'
}

# ── Driver ─────────────────────────────────────────────────────────────
echo
echo "$(green "HavenKeep store screenshot capture")"
echo "  Output → $OUT_BASE"
echo

require_running_api

if [[ "$PLATFORM" == "ios" ]]; then
  if [[ -n "$DEVICE_OVERRIDE" ]]; then
    ios_capture "$DEVICE_OVERRIDE"
  else
    for d in "${IOS_DEVICES[@]}"; do
      ios_capture "$d" || true
    done
  fi
else
  if [[ -n "$DEVICE_OVERRIDE" ]]; then
    android_capture "$DEVICE_OVERRIDE"
  else
    for d in "${ANDROID_DEVICES[@]}"; do
      android_capture "$d" || true
    done
  fi
fi

echo
echo "$(green "All done.")"
echo "  Upload from: $OUT_BASE"
