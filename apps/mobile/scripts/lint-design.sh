#!/usr/bin/env bash
# Design-system enforcement linter for the HavenKeep mobile app.
#
# Two modes:
#
#   `lint-design.sh`           — default. Lints ONLY the files staged
#                                for the current git commit. Designed
#                                to run as a pre-commit hook + in CI on
#                                the changed-files diff. Fails the
#                                commit if any forbidden pattern lands
#                                in new or modified lines.
#
#   `lint-design.sh --full`    — audit mode. Walks every dart file
#                                under apps/mobile/lib and reports
#                                every violation. Used to track
#                                outstanding Phase 1.5 debt. Always
#                                exits 0 — it's a report, not a gate.
#
# Five forbidden patterns:
#   1. Inline TextStyle(fontSize:)        — use HavenText.*
#   2. Raw Color(0xFF…) in features       — use HavenColors.*
#   3. Raw Material*Button in features    — use HavenButton
#   4. fullscreenDialog: true             — use a pushed route
#   5. Bare showModalBottomSheet          — use HavenSheet.show()
#
# Exemptions:
#   * `packages/shared_ui/` is excluded — primitives live there.
#   * `// design-lint-ignore-next-line` opts out of the next line.

set -euo pipefail

if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
FEATURES_DIR="$REPO_ROOT/apps/mobile/lib"

MODE="staged"
if [ "${1:-}" = "--full" ]; then
  MODE="full"
fi

EXIT_CODE=0

# --- Filter: drop lines preceded by `design-lint-ignore-next-line`. ---
filter_ignored() {
  awk '
    BEGIN { ignore_next = 0 }
    {
      if (ignore_next) { ignore_next = 0; next }
      if ($0 ~ /design-lint-ignore-next-line/) { ignore_next = 1; next }
      print
    }
  '
}

# --- The 5 forbidden patterns as a single function so both modes
# --- share one source of truth. ---
collect_violations() {
  local target_dir="$1"
  {
    grep -rnE 'TextStyle\(fontSize:' "$target_dir" --include="*.dart" \
      --exclude-dir=shared_ui 2>/dev/null \
      | sed 's|^|TextStyle:|'
    grep -rnE 'Color\(0x[0-9A-Fa-f]{8}\)' "$target_dir" --include="*.dart" \
      --exclude-dir=shared_ui 2>/dev/null \
      | sed 's|^|HexColor:|'
    grep -rnE '\b(ElevatedButton|FilledButton|OutlinedButton)\(' "$target_dir" \
      --include="*.dart" --exclude-dir=shared_ui 2>/dev/null \
      | sed 's|^|MaterialButton:|'
    grep -rnE 'fullscreenDialog:\s*true' "$target_dir" --include="*.dart" \
      --exclude-dir=shared_ui 2>/dev/null \
      | sed 's|^|FullscreenDialog:|'
    grep -rnE '\bshowModalBottomSheet\b' "$target_dir" --include="*.dart" \
      --exclude-dir=shared_ui 2>/dev/null \
      | sed 's|^|RawModalSheet:|'
  } || true
}

if [ "$MODE" = "full" ]; then
  # --------------------------------------------------------------------
  # Full audit mode. Walks the whole tree, reports everything,
  # exits 0. Used to track outstanding Phase 1.5 work.
  # --------------------------------------------------------------------
  echo "=== Design-system audit (every file under apps/mobile/lib) ==="
  echo
  violations="$(collect_violations "$FEATURES_DIR" | filter_ignored | sort)"
  if [ -z "$violations" ]; then
    echo "✓ Zero violations across the codebase. The design system is fully adopted."
    exit 0
  fi

  for rule in TextStyle HexColor MaterialButton FullscreenDialog RawModalSheet; do
    rule_hits="$(echo "$violations" | grep "^${rule}:" || true)"
    if [ -n "$rule_hits" ]; then
      count="$(echo "$rule_hits" | wc -l | tr -d ' ')"
      echo "── $rule ($count violations) ──"
      echo "$rule_hits" | sed "s|^${rule}:||" | sed 's/^/  /'
      echo
    fi
  done
  exit 0
fi

# ----------------------------------------------------------------------
# Staged mode (default). Only flag patterns that appear in lines staged
# for commit. Pre-existing debt is grandfathered until Phase 1.5 cleans
# it; the audit mode above is how we track that.
# ----------------------------------------------------------------------
staged_files="$(git diff --cached --name-only --diff-filter=ACMR -- 'apps/mobile/lib/**/*.dart' 2>/dev/null || true)"
if [ -z "$staged_files" ]; then
  echo "✓ No mobile/lib dart files staged. Design-system lint skipped."
  exit 0
fi

# Extract added lines + their absolute line numbers, then grep -E them.
# Awk handles the diff parsing; grep -E handles the forbidden-pattern match
# (avoids BSD-awk regex quirks like `\b`).
PATTERN='TextStyle\(fontSize:|Color\(0x[0-9A-Fa-f]{8}\)|(^|[^A-Za-z_])(ElevatedButton|FilledButton|OutlinedButton)\(|fullscreenDialog:[[:space:]]*true|(^|[^A-Za-z_])showModalBottomSheet([^A-Za-z_]|$)'

> /tmp/havenkeep-design-lint-$$.out
while IFS= read -r file; do
  [ -z "$file" ] && continue
  # Skip the shared_ui package — primitives live there.
  case "$file" in
    packages/shared_ui/*) continue ;;
  esac
  abs_file="$REPO_ROOT/$file"
  [ -f "$abs_file" ] || continue
  # `git diff --cached` returns the staged hunks. Walk hunk headers to
  # reconstruct the post-diff line number of each '+' line, then emit
  # `file:lineno:content` for each added line so we can grep it.
  hunks="$(git diff --cached -U0 -- "$file" 2>/dev/null || true)"
  [ -z "$hunks" ] && continue
  echo "$hunks" | awk -v file="$file" '
    /^@@/ {
      match($0, /\+[0-9]+/)
      lineno = substr($0, RSTART+1, RLENGTH-1) + 0
      next
    }
    /^\+\+\+/ { next }
    /^\+/ {
      content = substr($0, 2)
      if (content ~ /design-lint-ignore-next-line/) {
        skip_next = 1
        lineno++
        next
      }
      if (skip_next) {
        skip_next = 0
        lineno++
        next
      }
      printf "%s:%d:%s\n", file, lineno, content
      lineno++
      next
    }
    /^---/ { next }
    /^-/ { next }
    /^ / { lineno++ }
  ' | grep -E "$PATTERN" >> /tmp/havenkeep-design-lint-$$.out || true
done <<< "$staged_files"

violations="$(cat /tmp/havenkeep-design-lint-$$.out)"
rm -f /tmp/havenkeep-design-lint-$$.out

if [ -z "$violations" ]; then
  echo "✓ Design-system lint clean on staged changes."
  exit 0
fi

echo
echo "✗ Design-system lint FAILED on staged changes:"
echo
echo "$violations" | sed 's/^/  /'
echo
echo "Forbidden patterns:"
echo "  TextStyle(fontSize:)        → use HavenText.*"
echo "  Color(0xFF…) in features    → use HavenColors.*"
echo "  ElevatedButton / FilledButton / OutlinedButton → use HavenButton"
echo "  fullscreenDialog: true      → use a pushed route"
echo "  showModalBottomSheet        → use HavenSheet.show()"
echo
echo "If a violation is unavoidable, add // design-lint-ignore-next-line on the"
echo "preceding line and include a reason."
echo
echo "To see all outstanding violations across the codebase (audit mode):"
echo "  bash apps/mobile/scripts/lint-design.sh --full"
exit 1
