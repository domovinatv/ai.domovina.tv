#!/usr/bin/env bash
# Upload AAB na Google Play track preko Developer API-ja.
#   ./scripts/play-upload.sh internal   (default)
#   ./scripts/play-upload.sh production
# Auth: service account JSON (gcloud activate). Package: ai.domovina.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=ai.domovina
TRACK="${1:-internal}"
AAB=build/app/outputs/bundle/release/app-release.aab
# Release name = verzija iz pubspec-a (ranije hardkodirano "2.0.53" → stale)
APP_VER=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
KEY="${PLAY_SA_KEY:-$HOME/.config/play-publisher/domovina-play-publisher.json}"
API=https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PKG
UPLOAD=https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$PKG

[[ -f "$AAB" ]] || { echo "GRESKA: nema $AAB — pokreni ./scripts/build-mobile-release.sh android"; exit 1; }

gcloud auth activate-service-account --key-file="$KEY" >/dev/null 2>&1
TOKEN=$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher)
auth=(-H "Authorization: Bearer $TOKEN")

echo "==> edits.insert"
EDIT=$(curl -s "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["id"]')
echo "    editId=$EDIT"

echo "==> upload bundle ($(du -h "$AAB" | cut -f1))"
VC=$(curl -s "${auth[@]}" -H "Content-Type: application/octet-stream" \
  --data-binary @"$AAB" -X POST "$UPLOAD/edits/$EDIT/bundles?uploadType=media" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts d["versionCode"]')
echo "    versionCode=$VC"

echo "==> tracks.update ($TRACK, status=completed)"
curl -s "${auth[@]}" -H "Content-Type: application/json" -X PUT \
  "$API/edits/$EDIT/tracks/$TRACK" \
  -d '{"track":"'"$TRACK"'","releases":[{"name":"'"$APP_VER"' ('"$VC"')","versionCodes":["'"$VC"'"],"status":"completed"}]}' \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts "    track="+d["track"]'

echo "==> edits.commit"
curl -s "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits/$EDIT:commit" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts "    committed editId="+d["id"]'
echo "GOTOVO — AAB na '$TRACK' tracku, versionCode $VC."
