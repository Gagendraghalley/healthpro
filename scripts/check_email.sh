#!/usr/bin/env bash
# Is sign-in email working on the live project? Shows how it sends emails:
# Supabase's own test sender (only reaches the project's team, a few an hour)
# or your SMTP server (host, port, sender, hourly limit; never the password).
# Given an email address, also sends that account a real 6-digit code, as
# 'Forgot code?' on the sign-in page does; nothing about the account changes.
#
#   SUPABASE_ACCESS_TOKEN=sbp_... scripts/check_email.sh [someone@example.com]
#
# The address must already have an account (no account is made). Use your
# own, ideally one outside the Supabase team (e.g. a family member's), then
# look in that inbox, and its spam folder, within a minute or two.
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-iagqntjaywpdxvoxgfhl}"
: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN (supabase.com/dashboard/account/tokens)}"
api() { curl -fsS -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" "https://api.supabase.com/v1/projects/$PROJECT_REF/$1"; }

echo "== How project $PROJECT_REF sends email"
CONFIG_JSON="$(api config/auth)" node -e '
  const c = JSON.parse(process.env.CONFIG_JSON);
  const show = (label, value) => console.log(`   ${label.padEnd(20)} ${value ?? "(not set)"}`);
  if (!c.smtp_host) {
    console.log("   Supabase\x27s own test sender: it only delivers to the project\x27s team, about 2 an hour.");
    console.log("   Real users get no codes. Set SMTP (README, \"Email\") and run this again.");
    process.exit(2);
  }
  show("SMTP server", `${c.smtp_host}:${c.smtp_port}`);
  show("Signs in as", c.smtp_user);
  show("Sends from", `${c.smtp_sender_name || ""} <${c.smtp_admin_email}>`.trim());
  show("Emails an hour", c.rate_limit_email_sent);
  show("Code length", c.mailer_otp_length);
  show("Code lasts", c.mailer_otp_exp ? `${Math.round(c.mailer_otp_exp / 60)} minutes` : null);
  show("Subject", c.mailer_subjects_magic_link);
  if (!c.external_email_enabled) console.log("   ! Email sign-in is turned off (Authentication -> Providers -> Email).");
  if (![465, 587, "465", "587"].includes(c.smtp_port)) console.log("   ! Port 465 or 587 is usual.");
  const gmail = /gmail\.com$/i.test(c.smtp_host || "");
  if (gmail && c.smtp_admin_email && c.smtp_user && c.smtp_admin_email.toLowerCase() !== c.smtp_user.toLowerCase()) {
    console.log("   ! Gmail sends from the account it signs in as, unless the other address is set up as an alias.");
  }
  if (gmail && Number(c.rate_limit_email_sent) > 20) console.log("   (Gmail allows about 500 emails a day.)");
' || status=$?
if [[ "${status:-0}" == 2 ]]; then exit 2; fi
if [[ -n "${status:-}" ]]; then echo "Could not read the settings." >&2; exit 1; fi

email="${1:-}"
if [[ -z "$email" ]]; then
  echo
  echo "To send a real code: scripts/check_email.sh you@example.com"
  exit 0
fi

echo
echo "== Sending a code to $email"
anon="$(KEYS_JSON="$(api api-keys)" node -e '
  const keys = JSON.parse(process.env.KEYS_JSON);
  const key = keys.find((k) => k.type === "publishable") || keys.find((k) => k.name === "anon");
  if (!key) process.exit(1);
  process.stdout.write(key.api_key);
')"
body="$(EMAIL="$email" node -e 'process.stdout.write(JSON.stringify({ email: process.env.EMAIL.trim().toLowerCase(), create_user: false }))')"
answer="$(curl -sS -w '\n%{http_code}' -X POST "https://$PROJECT_REF.supabase.co/auth/v1/otp" \
  -H "apikey: $anon" -H 'Content-Type: application/json' -d "$body")"
code="$(tail -n1 <<< "$answer")"
reply="$(sed '$d' <<< "$answer")"
case "$code" in
  200) echo "   Sent. Look in that inbox (and spam) in a minute or two: the subject is your code email's." ;;
  429) echo "   Too many emails just now (the hourly limit, or one to this address a moment ago). Try again later." ;;
  *)
    echo "   Not sent ($code): $reply"
    if grep -qi 'signups not allowed\|user not found' <<< "$reply"; then
      echo "   There's no account with that email: use one that has signed up."
    elif grep -qi 'sending\|smtp\|email' <<< "$reply"; then
      echo "   The SMTP server refused it: check the user, the app password and the port in deploy.local.sh."
    fi
    exit 1
    ;;
esac
