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

# Auto-bump verzije na svakom deployu — pomaže korisniku znati treba li
# hard-refresh: ako footer prikazuje istu verziju kao prije, browser servira
# stari cache i potrebno je Cmd+Shift+R; ako je verzija nova, deploy je
# stigao do klijenta.
#
# Bumpa PATCH komponentu (treća) + build broj (+N). Skip s --no-bump flagom
# kad želiš redeployati istu verziju (npr. samo cache purge).
OLD_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
OLD_APP=$(echo "$OLD_VERSION" | cut -d'+' -f1)
OLD_BUILD=$(echo "$OLD_VERSION" | cut -d'+' -f2)

if [[ "${1:-}" == "--no-bump" ]]; then
  VERSION="$OLD_VERSION"
  APP_VERSION="$OLD_APP"
  echo "=== DOMOVINA.ai v${VERSION} (no bump) ==="
  shift
else
  # Inkrementiraj patch (treća komponenta) i build broj
  MAJOR=$(echo "$OLD_APP" | cut -d'.' -f1)
  MINOR=$(echo "$OLD_APP" | cut -d'.' -f2)
  PATCH=$(echo "$OLD_APP" | cut -d'.' -f3)
  NEW_PATCH=$((PATCH + 1))
  NEW_BUILD=$((OLD_BUILD + 1))
  APP_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
  VERSION="${APP_VERSION}+${NEW_BUILD}"

  echo "=== DOMOVINA.ai v${OLD_VERSION} → v${VERSION} ==="

  # Sync u pubspec.yaml (.bak fallback za macOS sed kompatibilnost)
  sed -i.bak "s/^version: ${OLD_VERSION}$/version: ${VERSION}/" pubspec.yaml
  rm -f pubspec.yaml.bak

  # Sync u lib/main.dart — appVersion konstanta koja se prikazuje u footeru
  sed -i.bak "s/const String appVersion = '${OLD_APP}';/const String appVersion = '${APP_VERSION}';/" lib/main.dart
  rm -f lib/main.dart.bak
fi

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

# 3b. Kopiraj fajlove koje Flutter build ne kopira automatski (robots.txt, ...)
#     Flutter web build kopira samo poznate fajlove iz web/ (index.html, manifest.json,
#     favicon.png, icons/, _headers, _worker.js, social-test.html). Ostalo dodajemo ovdje.
echo ""
echo "--- Copy extra web assets ---"
for f in robots.txt; do
  if [[ -f "web/$f" ]]; then
    cp "web/$f" "build/web/$f"
    echo "  copied $f"
  fi
done

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
