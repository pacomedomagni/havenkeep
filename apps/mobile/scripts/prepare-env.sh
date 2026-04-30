#!/usr/bin/env bash
#
# C15 (audit): copy the active flavor's env file into .env.bundled so
# pubspec.yaml ships only ONE env file in the IPA/APK assets bundle. The
# previous shape listed all three (.env.development, .env.staging,
# .env.production) under `assets:` — anyone with the binary could
# `unzip` and `cat` any of them in plaintext, including staging URLs
# and any future API keys an operator pasted in.
#
# Run this BEFORE `flutter build` (debug or release). The CI workflow at
# .github/workflows/mobile-ci.yml and the iOS deployment runbook at
# apps/mobile/IOS_DEPLOYMENT.md must call this script with the right
# flavor argument.
#
# Usage:
#   bash apps/mobile/scripts/prepare-env.sh production
#   bash apps/mobile/scripts/prepare-env.sh staging
#   bash apps/mobile/scripts/prepare-env.sh development
#
# Exits non-zero if the source file is missing — better to fail the
# build loudly than ship an empty .env.bundled that silently strips
# OAuth client IDs.

set -euo pipefail

FLAVOR="${1:-development}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

case "${FLAVOR}" in
  development|staging|production) ;;
  *)
    echo "prepare-env.sh: unknown flavor '${FLAVOR}'. Use development|staging|production." >&2
    exit 2
    ;;
esac

SRC="${MOBILE_DIR}/.env.${FLAVOR}"
DST="${MOBILE_DIR}/.env.bundled"

if [[ ! -f "${SRC}" ]]; then
  echo "prepare-env.sh: source env file not found at ${SRC}" >&2
  echo "  Either create it from .env.${FLAVOR}.example or pick a different flavor." >&2
  exit 1
fi

cp "${SRC}" "${DST}"
echo "prepare-env.sh: copied ${SRC} -> ${DST}"
