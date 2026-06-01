#!/usr/bin/env bash
# Lokalni dev run — Flutter web protiv LOKALNOG domovina-api Supabase stacka
# (NE prod api.domovina.ai). Edge funkcije (youtube-claim, certilia, …) i
# njihovi secreti žive u supabase/functions/.env u domovina-api repou.
#
# Lokalni stack: Kong 55321, DB 55322, Studio 55323 (553xx blok da ne kolidira
# sa zef stackom na default 5432x). Anon key je supabase-demo ključ — javan,
# isti za svaki lokalni CLI stack, smije u skriptu.
#
# Port 5173 je u GoTrue additional_redirect_urls allow-listi (vidi domovina-api
# config.toml) — ne mijenjaj bez dodavanja novog porta tamo.
set -euo pipefail

LOCAL_SUPABASE_URL="http://127.0.0.1:55321"
# supabase-demo anon key (javan, deterministički za lokalni CLI):
LOCAL_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

exec flutter run -d chrome --web-port 5173 \
  --dart-define=SUPABASE_URL="$LOCAL_SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$LOCAL_ANON_KEY" \
  "$@"
