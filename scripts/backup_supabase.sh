#!/usr/bin/env bash
# A copy of Health Pro's data, kept away from Supabase: the database (all the
# app's tables and functions, and the sign-in accounts) and every uploaded
# file (photos, certificates, payment QR codes). On Supabase's free plan this
# is the only backup there is; on Pro it's a second copy somewhere else.
#
#   SUPABASE_DB_PASSWORD=... SUPABASE_ACCESS_TOKEN=sbp_... scripts/backup_supabase.sh [folder]
#
# The same values as scripts/deploy_supabase.sh. Makes <folder>/<date-time>/
# (folder: backups/, which git ignores; put it somewhere that is itself
# backed up, e.g. a synced Google Drive folder):
#   database.dump   the public and private schemas: tables, data, functions,
#                   rules (pg_restore reads it)
#   accounts.sql    sign-in accounts (auth.users, auth.identities)
#   files/<bucket>/ every stored file, as it is in Storage (files.tsv lists them)
# Without SUPABASE_ACCESS_TOKEN the files are skipped; the rest still runs.
# How to restore: README.md, "Backups".
#
# Needs pg_dump at least as new as the database (Supabase runs PostgreSQL 15
# or 17): brew install postgresql@17. Reads only; changes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF="${SUPABASE_PROJECT_REF:-iagqntjaywpdxvoxgfhl}"
if [[ -z "${SUPABASE_DB_URL:-}" && "$PROJECT_REF" == iagqntjaywpdxvoxgfhl ]]; then
  SUPABASE_DB_URL='postgresql://postgres.iagqntjaywpdxvoxgfhl:[YOUR-PASSWORD]@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'
fi
: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL (the Session pooler string: dashboard, Connect button)}"
if [[ "$SUPABASE_DB_URL" == *'[YOUR-PASSWORD]'* ]]; then
  : "${SUPABASE_DB_PASSWORD:?Set SUPABASE_DB_PASSWORD (the database password of the project)}"
  # URL-encoded: '@', '+', '/' and the like would otherwise break the URL.
  password="$(P="$SUPABASE_DB_PASSWORD" node -e 'process.stdout.write(encodeURIComponent(process.env.P))')"
  db_url="${SUPABASE_DB_URL/\[YOUR-PASSWORD\]/$password}"
else
  db_url="$SUPABASE_DB_URL"
fi

# The newest PostgreSQL tools here: Homebrew's postgresql@17/16/15, then PATH.
bin=""
for dir in /opt/homebrew/opt/postgresql@17/bin /usr/local/opt/postgresql@17/bin \
           /opt/homebrew/opt/postgresql@16/bin /usr/local/opt/postgresql@16/bin \
           /opt/homebrew/opt/postgresql@15/bin /usr/local/opt/postgresql@15/bin; do
  if [[ -x "$dir/pg_dump" ]]; then bin="$dir/"; break; fi
done
pg_dump="${bin}pg_dump"
psql="${bin}psql"
server="$("$psql" "$db_url" -Atc 'show server_version_num')"
tools="$("$pg_dump" --version | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
if (( tools < server / 10000 )); then
  echo "pg_dump $tools is older than the database (PostgreSQL $((server / 10000))): brew install postgresql@$((server / 10000))" >&2
  exit 1
fi

out="${1:-backups}/$(date +%Y-%m-%d_%H%M)"
mkdir -p "$out"
echo "== Backing up to $out"

echo "== Database (public and private)"
"$pg_dump" "$db_url" --format=custom --no-owner --no-privileges --schema=public --schema=private \
  --file="$out/database.dump"

echo "== Sign-in accounts"
# Inserts that skip what's already there, so they load into a new project.
# The stored files' own records come back when the files are uploaded again.
"$pg_dump" "$db_url" --data-only --column-inserts --on-conflict-do-nothing --no-owner --no-privileges \
  --table=auth.users --table=auth.identities --file="$out/accounts.sql"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "== Files: skipped (set SUPABASE_ACCESS_TOKEN to copy them too)"
else
  echo "== Files"
  "$psql" "$db_url" -AtF $'\t' -c 'select bucket_id, name from storage.objects order by 1, 2' > "$out/files.tsv"
  keys="$(curl -fsS -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    "https://api.supabase.com/v1/projects/$PROJECT_REF/api-keys?reveal=true")"
  # The key that reads every bucket, private ones too; never printed.
  KEYS_JSON="$keys" PROJECT_REF="$PROJECT_REF" node -e '
    const fs = require("fs"), path = require("path");
    const keys = JSON.parse(process.env.KEYS_JSON);
    const key = (keys.find((k) => k.type === "secret") || keys.find((k) => k.name === "service_role") || {}).api_key;
    if (!key) { console.error("No secret (service_role) key found"); process.exit(1); }
    const headers = key.startsWith("sb_secret_") ? { apikey: key } : { apikey: key, Authorization: `Bearer ${key}` };
    const base = `https://${process.env.PROJECT_REF}.supabase.co/storage/v1/object`;
    const root = path.resolve(process.argv[1], "files");
    const list = fs.readFileSync(path.join(process.argv[1], "files.tsv"), "utf8").split("\n").filter(Boolean)
      .map((line) => line.split("\t"));
    let done = 0, failed = 0;
    async function one([bucket, name]) {
      const target = path.resolve(root, bucket, name);
      if (!target.startsWith(root + path.sep)) { failed++; return; }
      const url = `${base}/${encodeURIComponent(bucket)}/${name.split("/").map(encodeURIComponent).join("/")}`;
      try {
        const res = await fetch(url, { headers });
        if (!res.ok) throw new Error(`${res.status}`);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, Buffer.from(await res.arrayBuffer()));
        done++;
      } catch (e) {
        failed++;
        console.error(`   could not copy ${bucket}/${name} (${e.message})`);
      }
    }
    (async () => {
      for (let i = 0; i < list.length; i += 6) await Promise.all(list.slice(i, i + 6).map(one));
      console.log(`   ${done} of ${list.length} files copied` + (failed ? `, ${failed} not` : ""));
      if (failed) process.exitCode = 1;
    })();
  ' "$out"
fi

echo
echo "Done: $out ($(du -sh "$out" | cut -f1))"
