#!/usr/bin/env bash
# Checks the database end to end on a throwaway local Postgres: applies
# supabase/migrations to a stand-in for Supabase (tests/database/
# supabase_stub.sql), then plays an admin, a gym owner, front-desk staff and
# members through tests/database/scenario_test.sql, which checks every rule,
# then master data, roles and permissions through access_test.sql, and
# organisations and their own roles through organisations_test.sql, and Ask
# AI's daily question allowance through ai_test.sql, and one QR code per
# person and joining a gym by its QR code through people_test.sql, and
# paying online, the gym's settings and reminders through payments_test.sql,
# a venue's profile, prices and reviews through profile_test.sql, and
# trainers (verification, timings, attendance, reviews) through trainers_test.sql,
# and push notifications through push_test.sql, and each person's app colours
# through theme_test.sql, and their profile photo (and it in the gym's lists) through profile_photo_test.sql, and
# errors the app reports through app_errors_test.sql, and pausing memberships and
# numbered receipts through pauses_receipts_test.sql, and the activity log,
# enquiries, WhatsApp reminders and birthday wishes through follow_ups_test.sql, and
# the gym's inventory and connected suppliers through inventory_test.sql, and
# discounts, offers and expenses through money_test.sql, and body progress,
# workout and diet plans and group classes through coaching_test.sql, and the
# emails about classes through class_emails_test.sql.
# Needs PostgreSQL 14+ installed (brew install postgresql). Touches nothing else.
#
#   scripts/test_database.sh
set -euo pipefail
cd "$(dirname "$0")/.."

port="${PGTEST_PORT:-54329}"
dir="$(mktemp -d)"
cleanup() { pg_ctl -D "$dir/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$dir"; }
trap cleanup EXIT

initdb -D "$dir/data" -U postgres --auth=trust -E UTF8 --locale=C >/dev/null
pg_ctl -D "$dir/data" -o "-p $port -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" \
  -l "$dir/log.txt" -w start >/dev/null
db() { psql -h 127.0.0.1 -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

db -f tests/database/supabase_stub.sql 2>/dev/null
for migration in supabase/migrations/*.sql; do
  echo "Applying $(basename "$migration")"
  db -f "$migration" 2>&1 | grep -E "ERROR" && exit 1 || true
done
echo "Applying them again (they must be safe to re-run)"
for migration in supabase/migrations/*.sql; do db -f "$migration" >/dev/null 2>&1; done
db -f tests/database/scenario_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/access_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/organisations_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/registration_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/people_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/payments_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/profile_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/trainers_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/push_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/ai_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/theme_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/profile_photo_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/app_errors_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/pauses_receipts_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/follow_ups_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/inventory_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/money_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/coaching_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/class_emails_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
db -f tests/database/delete_member_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
echo "Applying supabase/seed.sql (local test data)"
db -f supabase/seed.sql
