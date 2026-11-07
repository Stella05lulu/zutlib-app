#!/bin/sh
# Fill the local Supabase with test accounts and sample data, so every screen
# can be tried without touching the real project. Run after `supabase start`.
# Safe to run again.
#
#   sh scripts/local_setup.sh
#
# The accounts and their one generated password go in .env.local-accounts,
# which is gitignored. They exist only on this Mac.
set -eu
cd "$(dirname "$0")/.."

eval "$(supabase status -o env 2>/dev/null)"

# Everything below writes, so refuse anything but this Mac.
case "$API_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing to run: $API_URL is not local." >&2; exit 1 ;;
esac

ACCOUNTS=.env.local-accounts
if [ -f "$ACCOUNTS" ]; then
  PASSWORD=$(sed -n 's/^PASSWORD=//p' "$ACCOUNTS")
else
  PASSWORD=$(openssl rand -hex 8)
  cat > "$ACCOUNTS" <<EOF
# Local test accounts for http://localhost:5001 on the local Supabase only.
PASSWORD=$PASSWORD
SUPER_ADMIN=local.super.admin@zutlib.test
LIBRARIAN=local.librarian@zutlib.test
STUDENT=sample.student.a@zutlib.test
SECOND_STUDENT=sample.student.b@zutlib.test
EOF
fi

sql() { docker exec -i supabase_db_zutlib psql -U postgres -q -v ON_ERROR_STOP=1 -At; }

for email in local.super.admin@zutlib.test local.librarian@zutlib.test \
             sample.student.a@zutlib.test sample.student.b@zutlib.test; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\",\"email_confirm\":true}")
  echo "account $email: $code"
done

SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" python3 scripts/sample_data.py seed

sql < scripts/seed_study_demo.sql > /dev/null
sed "s/target_email text := '[^']*'/target_email text := 'local.super.admin@zutlib.test'/" \
  scripts/restore_super_admin.sql | sql > /dev/null

sql > /dev/null <<'EOF'
begin;
select set_config('zutlib.break_glass', 'on', true);
update public.profiles p
   set role = 'librarian', status = 'active', decided_at = now()
  from auth.users u
 where u.id = p.id and lower(u.email) = 'local.librarian@zutlib.test';
commit;
EOF

sql < scripts/seed_demo_extras.sql > /dev/null
sql < scripts/seed_local_plan.sql > /dev/null

echo "Done. Accounts are in $ACCOUNTS"
