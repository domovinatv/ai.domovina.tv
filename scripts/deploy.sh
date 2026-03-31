#!/usr/bin/env bash
#
# DOMOVINA.ai — Build & Deploy
#
# Koristi:
#   ./scripts/deploy.sh          # release build + deploy + purge
#   ./scripts/deploy.sh --debug  # profile build (source maps, no minify) + deploy + purge
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Loadaj .env za Cloudflare tokene
if [[ -f .env ]]; then
  source .env
else
  echo "GRESKA: .env ne postoji — kopiraj .env.example u .env"
  exit 1
fi

# Provjeri da tokeni postoje
if [[ -z "${CLOUDFLARE_ZONE_ID:-}" || -z "${CLOUDFLARE_PURGE_TOKEN:-}" ]]; then
  echo "GRESKA: CLOUDFLARE_ZONE_ID i CLOUDFLARE_PURGE_TOKEN moraju biti u .env"
  exit 1
fi

# Izvuci verziju iz pubspec.yaml
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
APP_VERSION=$(echo "$VERSION" | cut -d'+' -f1)
echo "=== DOMOVINA.ai v${VERSION} ==="

# 1. Flutter pub get
echo ""
echo "--- flutter pub get ---"
flutter pub get

# 2. Analyze
echo ""
echo "--- flutter analyze ---"
flutter analyze || true

# 3. Build
echo ""
if [[ "${1:-}" == "--debug" ]]; then
  echo "--- flutter build web (profile + source-maps + O0) ---"
  flutter build web --profile --source-maps -O0
else
  echo "--- flutter build web (release) ---"
  flutter build web --release
fi

# 4. Deploy na Cloudflare Pages
echo ""
echo "--- wrangler pages deploy ---"
wrangler pages deploy build/web --project-name=domovina-ai --commit-dirty=true

# 5. Purge Cloudflare cache
echo ""
echo "--- Purge CDN cache ---"
PURGE_RESULT=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_PURGE_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}')

if echo "$PURGE_RESULT" | grep -q '"success":true'; then
  echo "Cache purged OK"
else
  echo "UPOZORENJE: Cache purge failed: $PURGE_RESULT"
fi

# 6. Verificiraj deployment
echo ""
echo "--- Verifikacija ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://domovina.ai/)
echo "https://domovina.ai/ -> HTTP $HTTP_CODE"

echo ""
echo "=== Deployed v${APP_VERSION} ==="
echo "Hard refresh: Cmd+Shift+R / Ctrl+Shift+R"
