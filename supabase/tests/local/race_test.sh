#!/usr/bin/env bash
# Last-copy race: two librarians approve two requests for the only copy of
# a book at the same moment. decide-request reserves the copy with
# reserve_copy(); exactly one of the two may succeed and the shelf count
# must end at zero, never below.
#
#   PGHOST=/tmp PGPORT=54322 PGUSER=postgres bash race_test.sh <database>
set -euo pipefail
DB="$1"
BOOK='00000000-0000-4000-8000-0000000009b1'
psql -q -d "$DB" -c "delete from public.resources where id = '$BOOK';
  insert into public.resources (id, title, type, department, author, is_physical, total_copies, available_copies)
  values ('$BOOK', 'Race test book', 'book', 'ICT', 'Race', true, 1, 1);"

# Session one takes the copy and holds its transaction open for a second;
# session two tries while it is still open.
OUT1=$(mktemp); OUT2=$(mktemp)
psql -qtA -d "$DB" -c "begin; select public.reserve_copy('$BOOK'); select pg_sleep(1); commit;" >"$OUT1" &
P1=$!
sleep 0.3
psql -qtA -d "$DB" -c "select public.reserve_copy('$BOOK');" >"$OUT2" &
P2=$!
wait $P1 $P2
A=$(grep -E '^(t|f)$' "$OUT1" | head -1); B=$(grep -E '^(t|f)$' "$OUT2" | head -1)
LEFT=$(psql -qtA -d "$DB" -c "select available_copies from public.resources where id = '$BOOK'")
psql -q -d "$DB" -c "delete from public.resources where id = '$BOOK'"
rm -f "$OUT1" "$OUT2"
echo "first approval reserved: $A   second approval reserved: $B   copies left: $LEFT"
if [ "$A" = "t" ] && [ "$B" = "f" ] && [ "$LEFT" = "0" ]; then
  echo "race_test: PASS (only one approval got the last copy)"
else
  echo "race_test: FAIL"; exit 1
fi
