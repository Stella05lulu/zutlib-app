#!/usr/bin/env bash
# ZutLib: run every database and Edge Function test on a throwaway local
# database. Nothing here touches the real Supabase project.
#
#   1. builds an empty database with supabase_shim.sql and every migration
#   2. runs the SQL security tests: rls_negative, study_rls, roles_rls,
#      study_kits_rls, planner_rls, super_admin_rls, plan_items_rls
#   3. runs the last-copy race test
#   4. starts PostgREST on that database and runs the Edge Function tests
#      (study-generate, admin-users and push), including both end-to-end tests
#
# Needs Postgres 15 or newer (psql and a running server), PostgREST 12 and
# Deno 2 on the PATH.
#
#   PGHOST=/tmp PGPORT=54322 PGUSER=postgres bash supabase/tests/local/run_local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DB="zutlib_local_test"
JWT_SECRET="local-test-secret-at-least-32-characters-long"
PGRST_PORT="${PGRST_PORT:-3010}"

bash "$ROOT/supabase/tests/local/fresh_db.sh" "$DB"
echo "migrations: all applied"

for t in rls_negative study_rls roles_rls study_kits_rls planner_rls super_admin_rls plan_items_rls; do
  result="$(psql -q -d "$DB" -P pager=off -f "$ROOT/supabase/tests/$t.sql" 2>&1)"
  pass=$(grep -cE '\| PASS *$' <<<"$result" || true)
  fail=$(grep -cE '\| FAIL *$' <<<"$result" || true)
  echo "$t.sql: $pass PASS, $fail FAIL"
  if [ "$fail" != "0" ]; then grep -E '\| FAIL *$' <<<"$result"; exit 1; fi
done

bash "$ROOT/supabase/tests/local/race_test.sh" "$DB"

CONF="$(mktemp)"
cat >"$CONF" <<EOF
db-uri = "postgres://authenticator:authenticator@/$DB?host=${PGHOST:-/tmp}&port=${PGPORT:-5432}"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "$JWT_SECRET"
server-port = $PGRST_PORT
server-host = "127.0.0.1"
EOF
postgrest "$CONF" >/dev/null 2>&1 &
PGRST_PID=$!
trap 'kill $PGRST_PID 2>/dev/null; rm -f "$CONF"' EXIT
for _ in $(seq 1 50); do
  curl -s "http://127.0.0.1:$PGRST_PORT/" >/dev/null && break
  sleep 0.2
done

export STUDY_E2E=1 PGRST_URL="http://127.0.0.1:$PGRST_PORT" JWT_SECRET="$JWT_SECRET" PSQL="psql -d $DB"
deno test --allow-env --allow-net --allow-run \
  "$ROOT/supabase/functions/study-generate/tests/" \
  "$ROOT/supabase/functions/admin-users/tests/" \
  "$ROOT/supabase/functions/push/tests/"
