#!/usr/bin/env bash
# Builds the website into apps/health_pro_app/build/web, here or on a host
# without Flutter (Cloudflare Pages fetches it first).
# Settings: apps/health_pro_app/env.json when it's there (your computer);
# otherwise the host's variables SUPABASE_URL and SUPABASE_ANON_KEY (and,
# optionally, GROUND_BOOKING_URL and VAPID_PUBLIC_KEY for push notifications).
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER_VERSION=3.38.5
if ! command -v flutter >/dev/null; then
  sdk="$HOME/flutter-$FLUTTER_VERSION"
  [ -x "$sdk/bin/flutter" ] ||
    git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$sdk"
  export PATH="$sdk/bin:$PATH"
fi

cd apps/health_pro_app
if [[ -f env.json ]]; then
  defines=(--dart-define-from-file=env.json)
else
  : "${SUPABASE_URL:?Add SUPABASE_URL to the build variables}"
  : "${SUPABASE_ANON_KEY:?Add SUPABASE_ANON_KEY to the build variables}"
  defines=(--dart-define=SUPABASE_URL="$SUPABASE_URL" --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
  if [[ -n "${GROUND_BOOKING_URL:-}" ]]; then defines+=(--dart-define=GROUND_BOOKING_URL="$GROUND_BOOKING_URL"); fi
  if [[ -n "${VAPID_PUBLIC_KEY:-}" ]]; then defines+=(--dart-define=VAPID_PUBLIC_KEY="$VAPID_PUBLIC_KEY"); fi
fi

flutter pub get
flutter build web --release "${defines[@]}" "$@"
