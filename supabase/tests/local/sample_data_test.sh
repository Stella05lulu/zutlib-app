#!/usr/bin/env bash
# ZutLib: tests for scripts/sample_data.py and for search at scale, on a
# throwaway local database (never the real project).
#
#   1. seed sample data twice and check it is idempotent (210 papers, 40 books)
#   2. search by keyword plus each filter, as an approved student, and time it
#   3. search again with 10,000 extra rows to show it stays fast
#   4. import real data from seed/real-papers and seed/real-books.csv,
#      with a report of accepted and rejected rows
#   5. remove all sample data in one step, leaving real data alone
#
# Needs Postgres, PostgREST, Deno and Python 3 on the PATH.
#   PGHOST=/tmp PGPORT=54322 PGUSER=postgres bash supabase/tests/local/sample_data_test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DB="zutlib_sample_test"
export JWT_SECRET="local-test-secret-at-least-32-characters-long"
PGRST_PORT="${PGRST_PORT:-3012}"
export PGRST_URL="http://127.0.0.1:$PGRST_PORT" PSQL="psql -d $DB"
Q() { psql -qtA -d "$DB" -c "$1"; }
fails=0
check() {  # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fails=$((fails+1)); fi
}

bash "$ROOT/supabase/tests/local/fresh_db.sh" "$DB"

CONF="$(mktemp)"; WORK="$(mktemp -d)"
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
deno run --allow-env --allow-net --allow-run "$ROOT/supabase/tests/local/serve_gateway.ts" >"$WORK/gw.json" &
GW_PID=$!
trap 'kill $PGRST_PID $GW_PID 2>/dev/null; rm -rf "$CONF" "$WORK"' EXIT
for _ in $(seq 1 50); do [ -s "$WORK/gw.json" ] && curl -s "$PGRST_URL/" >/dev/null && break; sleep 0.2; done
export SUPABASE_URL=$(python3 -c "import json;print(json.load(open('$WORK/gw.json'))['url'])")
export SUPABASE_SERVICE_ROLE_KEY=$(python3 -c "import json;print(json.load(open('$WORK/gw.json'))['service'])")

# ---------------------------------------------------------------- 1. seed
python3 "$ROOT/scripts/sample_data.py" seed
python3 "$ROOT/scripts/sample_data.py" seed >/dev/null
check "sample papers after seeding twice" 210 "$(Q "select count(*) from resources where is_sample and type in ('past_paper','test_paper')")"
check "sample books after seeding twice" 40 "$(Q "select count(*) from resources where is_sample and type = 'book'")"
check "sample PDF files stored" 210 "$(Q "select count(*) from storage.objects where bucket_id = 'resources' and name like 'sample/%'")"
check "years 2019 to 2025 covered" "2019-2025" "$(Q "select min(academic_year) || '-' || max(academic_year) from resources where is_sample")"
check "books with no copy on the shelf" 10 "$(Q "select count(*) from resources where is_sample and type = 'book' and available_copies = 0")"
check "every sample title says Sample" 0 "$(Q "select count(*) from resources where is_sample and title not ilike 'sample%'")"

# ---------------------------------------------------------------- 2. search
STUDENT=00000000-0000-4000-8000-00000000ee01
Q "insert into auth.users (id, email) values ('$STUDENT', 'search-student@example.invalid');
   update profiles set status = 'active' where id = '$STUDENT';" >/dev/null
TOKEN=$(cd "$ROOT/supabase/tests/local" && deno eval --ext=ts "import { jwt } from './gateway.ts'; console.log(await jwt({ sub: '$STUDENT', role: 'authenticated' }))")
search() {  # search <json params> -> number of results
  curl -s -X POST "$PGRST_URL/rpc/search_resources" -H "Authorization: Bearer $TOKEN" \
       -H "Content-Type: application/json" -d "$1" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))"
}
check "keyword: electric circuits, exams only" 7 "$(search '{"q":"electric circuits","p_type":"past_paper"}' )"
check "keyword + department, tests only" 7 "$(search '{"q":"circuits","p_department":"Engineering","p_type":"test_paper"}')"
check "keyword + course code (14 papers, 2 books)" 16 "$(search '{"q":"sample","p_course":"EEE 2021"}')"
TOP=$(curl -s -X POST "$PGRST_URL/rpc/search_resources" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d '{"q":"eee2021","p_limit":16}' | python3 -c "import sys,json;print(sum(r['course_code']=='EEE 2021' for r in json.load(sys.stdin)))")
check "course typed without a space: its 16 items come first" 16 "$TOP"
check "keyword + course + year" 2 "$(search '{"q":"circuits","p_course":"EEE 2021","p_year":2023}')"
check "keyword + department + year" 10 "$(search '{"q":"sample","p_department":"ICT","p_year":2020}')"
check "a small typo still matches (14 papers, 1 book)" 15 "$(search '{"q":"entreprenuership"}')"
check "books by author" 2 "$(search '{"q":"kotler","p_type":"book"}')"
check "page 2 of results" 50 "$(search '{"q":"sample","p_limit":50,"p_offset":50}')"
P1=$(curl -s -X POST "$PGRST_URL/rpc/search_resources" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"q":"sample","p_limit":20,"p_offset":0}' | python3 -c "import sys,json;print(','.join(sorted(r['id'] for r in json.load(sys.stdin))))")
P2=$(curl -s -X POST "$PGRST_URL/rpc/search_resources" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"q":"sample","p_limit":20,"p_offset":20}' | python3 -c "import sys,json;print(','.join(sorted(r['id'] for r in json.load(sys.stdin))))")
check "pages do not overlap" 0 "$(python3 -c "print(len(set('$P1'.split(','))&set('$P2'.split(','))))")"

timed() {  # median time in ms of 5 searches
  for _ in 1 2 3 4 5; do
    curl -s -o /dev/null -w "%{time_total}\n" -X POST "$PGRST_URL/rpc/search_resources" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$1"
  done | sort -n | sed -n 3p | python3 -c "import sys;print(int(float(sys.stdin.read())*1000))"
}
T1=$(timed '{"q":"data structures","p_department":"ICT"}')
echo "INFO  search over the seeded set (250 rows): ${T1} ms"

# ---------------------------------------------------------------- 3. scale
Q "insert into resources (title, type, department, course_code, course_title, academic_year, file_path, is_sample)
   select 'Sample load test ' || g || ' ' || (array['Calculus','Thermodynamics','Statistics','Robotics','Auditing'])[1 + g % 5],
          'past_paper', (array['ICT','Engineering','Business'])[1 + g % 3],
          'LDT ' || (1000 + g % 300), 'Load test course', 2000 + g % 26, 'load/' || g || '.pdf', true
   from generate_series(1, 10000) g; analyze resources;" >/dev/null
T2=$(timed '{"q":"data structures","p_department":"ICT"}')
T3=$(timed '{"q":"thermodynamics","p_year":2010}')
echo "INFO  search with 10,250 rows: ${T2} ms (keyword + department), ${T3} ms (keyword + year)"
check "search stays under 500 ms with 10,250 rows" yes "$([ "$T2" -lt 500 ] && [ "$T3" -lt 500 ] && echo yes || echo no)"
Q "delete from resources where file_path like 'load/%'" >/dev/null

# ---------------------------------------------------------------- 4. real data
mkdir -p "$WORK/real/seed/real-papers"
python3 -c "
import sys; sys.path.insert(0, '$ROOT/scripts')
from sample_data import make_pdf
open('$WORK/real/seed/real-papers/ICT_ICT 2010_2023_exam_Programming in C.pdf','wb').write(make_pdf([('Real paper stand-in', 12, False)]))
open('$WORK/real/seed/real-papers/badname.pdf','wb').write(make_pdf([('x', 12, False)]))
open('$WORK/real/seed/real-papers/ICT_ICT 1010_2022_quiz_Intro.pdf','wb').write(make_pdf([('x', 12, False)]))
"
cat >"$WORK/real/seed/real-books.csv" <<'CSV'
title,author,isbn,department,course_code,edition,total_copies
Real Book One,Author One,978-0-13-468599-1,ICT,ICT 2010,2nd,3
No Author Book,,,ICT,,,2
Wrong Department Book,Author Two,,Medicine,,,1
CSV
(cd "$WORK/real" && python3 "$ROOT/scripts/sample_data.py" import-real) | tee "$WORK/report.txt"
check "real rows accepted" "Accepted 2:" "$(grep -m1 '^Accepted' "$WORK/report.txt")"
check "bad rows rejected" "Rejected 4:" "$(grep -m1 '^Rejected' "$WORK/report.txt")"
check "real rows are not marked sample" 2 "$(Q "select count(*) from resources where not is_sample and (title like 'ICT 2010 Programming%' or title = 'Real Book One')")"

# ---------------------------------------------------------------- 5. remove
python3 "$ROOT/scripts/sample_data.py" remove
check "sample rows after remove" 0 "$(Q "select count(*) from resources where is_sample")"
check "sample files after remove" 0 "$(Q "select count(*) from storage.objects where name like 'sample/%'")"
check "real rows kept" 2 "$(Q "select count(*) from resources where not is_sample")"
python3 "$ROOT/scripts/sample_data.py" remove >/dev/null
check "remove twice is harmless" 0 "$(Q "select count(*) from resources where is_sample")"

echo
if [ "$fails" = "0" ]; then echo "sample_data_test: all checks PASS"; else echo "sample_data_test: $fails FAIL"; exit 1; fi
