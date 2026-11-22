#!/usr/bin/env bash
# Builds the website and publishes it to the Cloudflare Pages project
# 'myhealthpro' (https://myhealthpro.pages.dev), as a push to main would.
#
#   CLOUDFLARE_API_TOKEN=... scripts/deploy_web.sh
#
# CLOUDFLARE_API_TOKEN: dash.cloudflare.com/profile/api-tokens -> Create Token ->
# Custom token, permission Account -> Cloudflare Pages -> Edit. (Or run
# `npx wrangler login` once instead.)
# Needs apps/health_pro_app/env.json (scripts/deploy_supabase.sh writes it).
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f apps/health_pro_app/env.json ]] || { echo "apps/health_pro_app/env.json is missing (README, 'Run the app')." >&2; exit 1; }
bash scripts/build_web.sh
export npm_config_cache="${TMPDIR:-/tmp}/health-pro-npm-cache"
npx -y wrangler@4 pages deploy apps/health_pro_app/build/web --project-name myhealthpro --branch main --commit-dirty=true
