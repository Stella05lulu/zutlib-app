#!/usr/bin/env bash
# Builds an empty database named $1 with the shim and every migration.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DB="$1"
psql -q -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE || true
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/local/supabase_shim.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1 | { grep -v NOTICE || true; }
done
