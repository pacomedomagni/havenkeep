#!/usr/bin/env bash
#
# Pre-production check: is the audit-log hash chain actually tamper-evident?
#
# Migrations 099/100/101 reassign `audit_logs` (and its trigger functions)
# to the `audit_cleaner` role and revoke the API role's UPDATE/DELETE. That
# only works as tamper-evidence if BOTH of these hold on the live DB:
#
#   1. The ALTER OWNER statements actually ran  →  audit_logs.owner =
#      'audit_cleaner', and migrations 099/100/101 are recorded in
#      schema_version.
#   2. The API role (`havenkeep`) is NOT a member of `audit_cleaner`  —
#      otherwise the BEFORE UPDATE/DELETE immutable trigger's
#      `pg_has_role(current_user, 'audit_cleaner', 'MEMBER')` check passes
#      for it and the append-only guard is bypassable by anyone with API
#      DB credentials.
#
# Postgres only lets a non-superuser ALTER ... OWNER TO a role it is a
# member of — so (1) and (2) are in tension when the migration runner uses
# the API role. The likely failure modes:
#   • migrations 099/100/101 threw on first run  →  chain hardening absent
#   • the migration role IS a member of audit_cleaner  →  trigger bypassable
#   • migrations were run by a superuser  →  both can be true (the good case)
#
# Run this against the production (and staging) DB before going live:
#
#   DATABASE_URL='postgresql://USER:PASS@HOST:PORT/havenkeep' \
#     ./scripts/verify-audit-isolation.sh
#
# Or pass a psql connection string / use the standard PG* env vars.
# Read-only — it only SELECTs. Exits non-zero if anything looks wrong.

set -euo pipefail

# Use `psql` if it's on PATH; otherwise, if PSQL_DOCKER_CONTAINER is set,
# run psql inside that container (handy for the docker-compose dev/test DB
# where psql isn't installed on the host). On the prod droplet psql is
# present, so the env var is only for local convenience.
if command -v psql >/dev/null 2>&1; then
  PSQL=(psql -v ON_ERROR_STOP=1 --no-psqlrc --quiet --tuples-only --no-align)
  [[ -n "${DATABASE_URL:-}" ]] && PSQL+=("$DATABASE_URL")
elif [[ -n "${PSQL_DOCKER_CONTAINER:-}" ]]; then
  PSQL=(docker exec -i "$PSQL_DOCKER_CONTAINER"
        psql -v ON_ERROR_STOP=1 --no-psqlrc --quiet --tuples-only --no-align)
  [[ -n "${DATABASE_URL:-}" ]] && PSQL+=("$DATABASE_URL")
else
  echo "Need either 'psql' on PATH (with DATABASE_URL set), or" >&2
  echo "PSQL_DOCKER_CONTAINER=<name> to run psql inside a container." >&2
  exit 2
fi

# The API role whose membership we care about. Override if your prod role
# has a different name (e.g. `havenkeep_api`).
API_ROLE="${API_ROLE:-havenkeep}"

q() { "${PSQL[@]}" -c "$1"; }

echo "── Audit-chain isolation check ──────────────────────────────────────"
echo "API role under test: ${API_ROLE}"
echo

fail=0

# 1) audit_logs table owner
owner="$(q "SELECT pg_get_userbyid(relowner) FROM pg_class WHERE relname = 'audit_logs' AND relkind = 'r';")"
echo "audit_logs owner            : ${owner:-<table not found!>}"
if [[ "$owner" != "audit_cleaner" ]]; then
  echo "  ✗ EXPECTED 'audit_cleaner' — migrations 099/100/101 may not have applied,"
  echo "    or were rolled back, or the table was re-owned. Chain hardening is NOT in place."
  fail=1
else
  echo "  ✓ owned by audit_cleaner"
fi
echo

# 2) trigger function owners (assign-hash + immutable guard + verifier)
for fn in audit_logs_assign_hash audit_logs_immutable verify_audit_chain cleanup_old_audit_logs; do
  fnowner="$(q "SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE proname = '${fn}' LIMIT 1;" || true)"
  if [[ -z "$fnowner" ]]; then
    echo "function ${fn}: <not found>  ✗ (expected to exist)"
    fail=1
  elif [[ "$fnowner" != "audit_cleaner" ]]; then
    echo "function ${fn}: owned by ${fnowner}  ✗ (expected audit_cleaner)"
    fail=1
  else
    echo "function ${fn}: owned by audit_cleaner  ✓"
  fi
done
echo

# 3) API role must NOT be a member of audit_cleaner (directly or via grant)
is_member="$(q "SELECT pg_has_role('${API_ROLE}', 'audit_cleaner', 'MEMBER');" || echo 'role-or-target-missing')"
echo "pg_has_role('${API_ROLE}', 'audit_cleaner', 'MEMBER') = ${is_member}"
if [[ "$is_member" == "t" ]]; then
  echo "  ✗ The API role IS a member of audit_cleaner — the immutable BEFORE"
  echo "    UPDATE/DELETE trigger's pg_has_role(...) check passes for it, so"
  echo "    audit_logs is editable by anyone with API DB credentials. The"
  echo "    tamper-evidence guarantee does NOT hold. Revoke the membership"
  echo "    (and reconsider how migrations get the OWNER reassignment to run —"
  echo "    e.g. apply migrations as a superuser, not the API role)."
  fail=1
elif [[ "$is_member" == "f" ]]; then
  echo "  ✓ API role is not a member of audit_cleaner"
else
  echo "  ✗ Could not evaluate (role '${API_ROLE}' or 'audit_cleaner' missing). Investigate."
  fail=1
fi
echo

# 4) API role privileges on audit_logs: should be SELECT + INSERT only
privs="$(q "SELECT string_agg(privilege_type, ',' ORDER BY privilege_type)
              FROM information_schema.role_table_grants
             WHERE table_name = 'audit_logs' AND grantee = '${API_ROLE}';" || true)"
echo "${API_ROLE} privileges on audit_logs: ${privs:-<none>}"
case "$privs" in
  "INSERT,SELECT"|"SELECT,INSERT"|"INSERT"|"SELECT") echo "  ✓ no UPDATE/DELETE/TRUNCATE granted" ;;
  *UPDATE*|*DELETE*|*TRUNCATE*) echo "  ✗ UPDATE/DELETE/TRUNCATE present — should have been revoked (mig 101)"; fail=1 ;;
  "") echo "  ⚠ no grants found — the API role may be unable to write audit rows at all; verify INSERT is granted" ;;
  *) echo "  ⚠ unexpected grant set — review" ;;
esac
echo

# 5) the migrations we depend on are recorded
recorded="$(q "SELECT string_agg(version::text, ',' ORDER BY version)
                 FROM schema_version
                WHERE version::text = ANY (ARRAY['099','100','101','031','065']);" || echo '<schema_version unreadable>')"
echo "recorded migrations among {031,065,099,100,101}: ${recorded:-<none>}"
for m in 031 065 099 100 101; do
  if [[ ",$recorded," != *",$m,"* ]]; then
    echo "  ✗ migration ${m} not recorded in schema_version"
    fail=1
  fi
done
[[ "$fail" == 0 ]] && echo "  ✓ all five recorded" || true
echo

# 6) sanity: the chain currently verifies clean
broken="$(q "SELECT count(*) FROM verify_audit_chain();" || echo 'verify-fn-missing')"
echo "verify_audit_chain() broken-row count: ${broken}"
if [[ "$broken" == "0" ]]; then
  echo "  ✓ chain intact"
elif [[ "$broken" == "verify-fn-missing" ]]; then
  echo "  ✗ verify_audit_chain() not callable — chain verification is not wired"
  fail=1
else
  echo "  ✗ ${broken} broken link(s) — investigate immediately (possible tampering or a TZ/cast regression)"
  fail=1
fi
echo "─────────────────────────────────────────────────────────────────────"

if [[ "$fail" == 0 ]]; then
  echo "PASS — audit-log tamper-evidence is correctly isolated."
  exit 0
else
  echo "FAIL — see ✗ items above. Do not rely on the 'even an admin can't tamper'"
  echo "       guarantee until these are resolved."
  exit 1
fi
