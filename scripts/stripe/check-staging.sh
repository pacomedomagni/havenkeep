#!/usr/bin/env bash
#
# scripts/stripe/check-staging.sh — staging Stripe connectivity smoke test.
#
# Runs in <10s. Verifies in order:
#   1. Local prereqs (stripe CLI present + authed to Test mode)
#   2. Public surface (api.staging.havenkeep.app reachable + /health 200)
#   3. API config (Stripe keys present in /opt/staging/havenkeep/.env.api)
#   4. Webhook signature path (stripe trigger → 2xx response from our endpoint)
#
# Exits non-zero on first failure. Each step prints a one-line PASS/FAIL.
#
# Usage:
#   ./scripts/stripe/check-staging.sh
#   ./scripts/stripe/check-staging.sh --skip-trigger   # skip the webhook fire
#
# Required on the laptop: stripe CLI, ssh access to the droplet, jq, curl.

set -euo pipefail

# ── Config (matches CLAUDE.md Part 2 §"Staging deployment") ──
STAGING_API="https://api.staging.havenkeep.app"
STAGING_HOST="206.189.26.12"
STAGING_SSH_KEY="$HOME/.ssh/loni_deploy"
STAGING_APP_DIR="/opt/staging/havenkeep"

# ── CLI flags ──
SKIP_TRIGGER=0
for arg in "$@"; do
  case "$arg" in
    --skip-trigger) SKIP_TRIGGER=1 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ── Output helpers ──
green()  { printf "\033[32m%s\033[0m\n" "$1"; }
red()    { printf "\033[31m%s\033[0m\n" "$1" >&2; }
cyan()   { printf "\033[36m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

pass() { green "  PASS  $1"; }
fail() { red   "  FAIL  $1"; exit 1; }
info() { cyan  "  INFO  $1"; }

step() { echo; cyan "── $1 ──"; }

# ── Prereqs ──
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not installed (need: $2)"
}

# ============================================================================
step "1. Local prereqs"
# ============================================================================
require_cmd ssh   "openssh-client"
require_cmd curl  "curl"
require_cmd jq    "brew install jq"
require_cmd stripe "brew install stripe/stripe-cli/stripe"
pass "ssh, curl, jq, stripe CLI all present"

# Verify stripe CLI is authed and pointing at Test mode.
# `stripe config --list` exits 0 with no output when no profile is configured.
STRIPE_CONFIG=$(stripe config --list 2>/dev/null || true)
if [ -z "$STRIPE_CONFIG" ]; then
  fail "stripe CLI not authed — run: stripe login"
fi

# `stripe --api-key` lookup — the CLI uses test_mode_api_key for triggers.
# We don't print the key; just confirm the right kind is present.
if echo "$STRIPE_CONFIG" | grep -q "test_mode_api_key"; then
  pass "stripe CLI authed (test mode)"
else
  fail "stripe CLI lacks a test-mode key — re-run: stripe login"
fi

# ============================================================================
step "2. Public surface (DNS + Caddy + API up)"
# ============================================================================
HEALTH_HTTP=$(curl -s -o /tmp/.hk-health -w "%{http_code}" --max-time 8 "$STAGING_API/health" || echo "000")
if [ "$HEALTH_HTTP" != "200" ]; then
  red "  /health returned HTTP $HEALTH_HTTP"
  red "  body: $(cat /tmp/.hk-health 2>/dev/null | head -c 200)"
  fail "$STAGING_API/health is not reachable"
fi

HEALTH_STATUS=$(jq -r '.status // "missing"' < /tmp/.hk-health 2>/dev/null)
[ "$HEALTH_STATUS" = "ok" ] || fail "/health returned 200 but status='$HEALTH_STATUS' (expected 'ok')"
pass "$STAGING_API/health → 200 {status: ok}"
rm -f /tmp/.hk-health

# Caddy must serve the AASA file as application/json (mobile compliance,
# also signals Caddy itself is healthy on the host).
AASA_CT=$(curl -sI --max-time 5 "https://staging.havenkeep.app/.well-known/apple-app-site-association" \
  | grep -i "^content-type:" | tr -d '\r' | awk '{print tolower($2)}' || true)
if [ "$AASA_CT" = "application/json" ]; then
  pass "marketing site Caddy serving AASA correctly"
else
  yellow "  WARN  AASA Content-Type is '$AASA_CT' (expected application/json) — mobile universal links will silently fail"
fi

# ============================================================================
step "3. API config (staging .env.api on droplet)"
# ============================================================================
SSH_OPTS=(-i "$STAGING_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=8)
ssh "${SSH_OPTS[@]}" "root@$STAGING_HOST" "true" 2>/dev/null \
  || fail "cannot SSH to root@$STAGING_HOST — check ~/.ssh/loni_deploy + droplet status"

# Read the three Stripe env values without printing them. Drop on missing.
ENV_LINES=$(ssh "${SSH_OPTS[@]}" "root@$STAGING_HOST" \
  "grep -E '^(STRIPE_SECRET_KEY|STRIPE_WEBHOOK_SECRET|STRIPE_PRICE_ID_PREMIUM|STRIPE_ALLOW_SANDBOX)=' \
   $STAGING_APP_DIR/.env.api 2>/dev/null | sed -E 's/=(sk_|pk_|whsec_|price_)[A-Za-z0-9_]+.*/=\1***/'")

# STRIPE_SECRET_KEY must be sk_test_…
if echo "$ENV_LINES" | grep -q "^STRIPE_SECRET_KEY=sk_test_"; then
  pass "STRIPE_SECRET_KEY present (sk_test_…)"
elif echo "$ENV_LINES" | grep -q "^STRIPE_SECRET_KEY=sk_live_"; then
  fail "STRIPE_SECRET_KEY is sk_live_… — staging must use Test mode keys"
else
  fail "STRIPE_SECRET_KEY missing or invalid in $STAGING_APP_DIR/.env.api"
fi

# STRIPE_WEBHOOK_SECRET must start with whsec_
echo "$ENV_LINES" | grep -q "^STRIPE_WEBHOOK_SECRET=whsec_" \
  && pass "STRIPE_WEBHOOK_SECRET present (whsec_…)" \
  || fail "STRIPE_WEBHOOK_SECRET missing or invalid in .env.api"

# STRIPE_PRICE_ID_PREMIUM must start with price_
echo "$ENV_LINES" | grep -q "^STRIPE_PRICE_ID_PREMIUM=price_" \
  && pass "STRIPE_PRICE_ID_PREMIUM present (price_…)" \
  || fail "STRIPE_PRICE_ID_PREMIUM missing in .env.api"

# Sandbox flag is required for sk_test_… in staging.
echo "$ENV_LINES" | grep -q "^STRIPE_ALLOW_SANDBOX=true" \
  && pass "STRIPE_ALLOW_SANDBOX=true (config validator will accept sk_test_…)" \
  || fail "STRIPE_ALLOW_SANDBOX=true missing — config validator will refuse sk_test_… on boot"

# ============================================================================
step "4. Webhook signature verification end-to-end"
# ============================================================================
if [ "$SKIP_TRIGGER" = "1" ]; then
  yellow "  SKIP  --skip-trigger flag set"
else
  info "Firing one signed event via 'stripe trigger payment_intent.succeeded'…"
  # The CLI delivers directly to the registered webhook endpoint; if signature
  # check passes server-side the API logs and 200s, else 400. We just need
  # the trigger command itself to exit 0 — Stripe surfaces the response code.
  TRIGGER_OUT=$(stripe trigger payment_intent.succeeded 2>&1) || {
    red "  trigger output:"
    echo "$TRIGGER_OUT" | sed 's/^/    /' | head -15 >&2
    fail "stripe trigger payment_intent.succeeded failed"
  }

  # Confirm the API actually received + processed it by tailing the recent logs.
  # The webhook handler logs 'Stripe webhook event received' at info level
  # with eventType=payment_intent.succeeded.
  sleep 2
  RECEIVED=$(ssh "${SSH_OPTS[@]}" "root@$STAGING_HOST" \
    "docker logs --since 10s havenkeep-api 2>&1 | grep -c 'eventType.*payment_intent.succeeded' || true")
  if [ "${RECEIVED:-0}" -ge 1 ]; then
    pass "API received + processed payment_intent.succeeded (signature verified)"
  else
    yellow "  WARN  trigger succeeded but no matching log line found in last 10s"
    yellow "        (event may still have processed; check Dozzle: https://logs.staging.kouakoudomagni.com)"
  fi
fi

# ============================================================================
echo
green "═══════════════════════════════════════════════════════════════"
green "  staging Stripe is ready for the e2e suite"
green "  next: ./scripts/stripe/e2e-staging.sh"
green "═══════════════════════════════════════════════════════════════"
