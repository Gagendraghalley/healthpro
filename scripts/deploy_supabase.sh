#!/usr/bin/env bash
# Puts Health Pro's whole backend on its Supabase project:
#   1. the database: supabase/migrations (tables, security rules, functions,
#      the daily gym job), only those not applied yet;
#   2. the Edge Functions: supabase/functions;
#   3. the auth settings in supabase/config.toml (6-digit email codes, their
#      email template, password length);
#   4. apps/health_pro_app/env.json for running the app, if it isn't there.
#
#   SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
#
# SUPABASE_ACCESS_TOKEN: supabase.com/dashboard/account/tokens -> Generate new token.
# SUPABASE_DB_PASSWORD:  the database password chosen when the project was made
#                        (Database -> Settings -> Reset database password).
# SUPABASE_DB_URL:       optional. The database is reached through the Session
#                        pooler, which works on networks without IPv6; this
#                        project's is built in. For another project, its Session
#                        pooler string from the dashboard's Connect button,
#                        [YOUR-PASSWORD] and all; the password goes in from
#                        SUPABASE_DB_PASSWORD.
# CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_AI_TOKEN: optional. Turn on Ask AI
#                        (Cloudflare Workers AI); they're stored as the
#                        Edge Functions' secrets (ask-ai, ask-health-pro).
#                        Once is enough.
# VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY: optional. Turn on push
#                        notifications (scripts/make_push_keys.ts makes them,
#                        once; never change them). The private key becomes the
#                        send-push function's secret; the public one goes into
#                        env.json for the app. VAPID_SUBJECT: who sends them
#                        (mailto:... or the site's address; the website's by
#                        default).
# No secret is saved in the project.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF="${SUPABASE_PROJECT_REF:-iagqntjaywpdxvoxgfhl}"
: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN (supabase.com/dashboard/account/tokens)}"
: "${SUPABASE_DB_PASSWORD:?Set SUPABASE_DB_PASSWORD (the database password of the project)}"
# Health Pro's own Session pooler (no secret in it). Only for Health Pro: another
# project falls back to a direct connection unless SUPABASE_DB_URL is set.
if [[ -z "${SUPABASE_DB_URL:-}" && "$PROJECT_REF" == iagqntjaywpdxvoxgfhl ]]; then
  SUPABASE_DB_URL='postgresql://postgres.iagqntjaywpdxvoxgfhl:[YOUR-PASSWORD]@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'
fi
export SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD

# Supabase CLI 3 (its flags differ from 2's), through npx with its own
# cache so a broken ~/.npm cache doesn't get in the way.
export npm_config_cache="${TMPDIR:-/tmp}/health-pro-npm-cache"
sb() { npx -y supabase@3 "$@"; }

echo "== Linking to project $PROJECT_REF"
sb link --project-ref "$PROJECT_REF" --yes

echo "== Database: applying new migrations"
if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
  # Through the pooler (IPv4). The password is URL-encoded: '@', '+', '/' and
  # the like would otherwise break the URL.
  password="$(node -e 'process.stdout.write(encodeURIComponent(process.env.SUPABASE_DB_PASSWORD))')"
  sb db push --remote="${SUPABASE_DB_URL/\[YOUR-PASSWORD\]/$password}" --yes
else
  sb db push --remote --password "$SUPABASE_DB_PASSWORD" --yes
fi

echo "== Edge Functions"
sb functions deploy --use-api --yes

if [[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" && -n "${CLOUDFLARE_AI_TOKEN:-}" ]]; then
  echo "== Ask AI: Cloudflare Workers AI secrets"
  # Through a private file, so the token isn't on the command line.
  secrets="$(mktemp)"
  trap 'rm -f "$secrets"' EXIT
  printf 'CLOUDFLARE_ACCOUNT_ID=%s\nCLOUDFLARE_AI_TOKEN=%s\n' "$CLOUDFLARE_ACCOUNT_ID" "$CLOUDFLARE_AI_TOKEN" > "$secrets"
  sb secrets set --env-file "$secrets" --yes
  rm -f "$secrets"
fi

if [[ -n "${VAPID_PUBLIC_KEY:-}" && -n "${VAPID_PRIVATE_KEY:-}" ]]; then
  echo "== Push notifications: VAPID keys"
  secrets="$(mktemp)"
  trap 'rm -f "$secrets"' EXIT
  printf 'VAPID_PUBLIC_KEY=%s\nVAPID_PRIVATE_KEY=%s\nVAPID_SUBJECT=%s\n' \
    "$VAPID_PUBLIC_KEY" "$VAPID_PRIVATE_KEY" "${VAPID_SUBJECT:-https://sporthubs.pages.dev}" > "$secrets"
  sb secrets set --env-file "$secrets" --yes
  rm -f "$secrets"
fi

echo "== Push notifications: telling the database where send-push is"
curl -fsS -X POST "https://$PROJECT_REF.supabase.co/functions/v1/send-push" \
  -H 'Content-Type: application/json' -d '{"setup":true}' && echo ||
  echo "   (send-push didn't answer; run this script again later)"

echo "== Auth settings (email codes)"
sb config push --yes

env_file=apps/health_pro_app/env.json
if [[ ! -f "$env_file" ]]; then
  echo "== Writing $env_file"
  keys_json="$(sb projects api-keys -o json)"
  KEYS_JSON="$keys_json" PROJECT_REF="$PROJECT_REF" node -e '
    const parsed = JSON.parse(process.env.KEYS_JSON);
    const keys = Array.isArray(parsed) ? parsed : (parsed.keys || parsed.api_keys || []);
    const pick = (k) => k.find((x) => x.name === "anon") || k.find((x) => (x.type || "") === "publishable");
    const key = pick(keys);
    if (!key) { console.error("No anon/publishable key found"); process.exit(1); }
    const env = {
      SUPABASE_URL: `https://${process.env.PROJECT_REF}.supabase.co`,
      SUPABASE_ANON_KEY: key.api_key,
      GROUND_BOOKING_URL: "https://kuzuhelp.com",
    };
    require("fs").writeFileSync(process.argv[1], JSON.stringify(env, null, 2) + "\n");
  ' "$env_file"
fi
if [[ -n "${VAPID_PUBLIC_KEY:-}" && -f "$env_file" ]]; then
  # The app subscribes with the public key (not a secret).
  VAPID_PUBLIC_KEY="$VAPID_PUBLIC_KEY" node -e '
    const fs = require("fs");
    const env = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    env.VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY;
    fs.writeFileSync(process.argv[1], JSON.stringify(env, null, 2) + "\n");
  ' "$env_file"
fi

echo
echo "Done. Next:"
echo "  - Make yourself an admin (README, 'Make yourself an admin')."
echo "  - Run the website: ./scripts/run_web.sh   (http://localhost:3000)"
