#!/bin/sh
# Choose which Supabase project the app builds against. The app bundles .env
# at build time, so rebuild after switching.
#
#   sh scripts/use_backend.sh local        the throwaway Supabase on this Mac
#   sh scripts/use_backend.sh production   the real project
#   sh scripts/use_backend.sh              says which one .env points at
#
# .env.production holds the real values. It and .env are gitignored.
set -eu
cd "$(dirname "$0")/.."

case "${1:-}" in
  local)
    eval "$(supabase status -o env 2>/dev/null)"
    [ -f .env.production ] || cp .env .env.production
    printf 'SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\n' "$API_URL" "$ANON_KEY" > .env
    ;;
  production)
    cp .env.production .env
    ;;
  "") ;;
  *) echo "Use: local or production" >&2; exit 1 ;;
esac

if grep -qE '^SUPABASE_URL=.*(127\.0\.0\.1|localhost)' .env; then
  echo "App backend: LOCAL (test data only)"
else
  echo "App backend: PRODUCTION (real data)"
fi
