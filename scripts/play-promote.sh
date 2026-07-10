#!/usr/bin/env bash
# Promovira VEĆ UPLOADANI versionCode na Play track (bez re-uploada AAB-a —
# edits.bundles.upload istog versionCodea pada, zato ovo nije play-upload.sh).
#   ./scripts/play-promote.sh <versionCode> [track] [release-notes-hr]
#   ./scripts/play-promote.sh 96 production "Novosti: …"
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=ai.domovina
VC="${1:?versionCode obavezan (npr. 96)}"
TRACK="${2:-production}"
NOTES="${3:-}"
KEY="${PLAY_SA_KEY:-$HOME/.config/play-publisher/domovina-play-publisher.json}"
API=https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PKG
APP_VER=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)

gcloud auth activate-service-account --key-file="$KEY" >/dev/null 2>&1
TOKEN=$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher)
auth=(-H "Authorization: Bearer $TOKEN")

RELEASE=$(ruby -rjson -e 'r={"name"=>"'"$APP_VER"' ('"$VC"')","versionCodes"=>["'"$VC"'"],"status"=>"completed"};
n=ARGV[0]; r["releaseNotes"]=[{"language"=>"hr","text"=>n}] unless n.to_s.empty?;
puts({"track"=>"'"$TRACK"'","releases"=>[r]}.to_json)' "$NOTES")

echo "==> edits.insert"
EDIT=$(curl -s --retry 3 "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["id"]')
echo "    editId=$EDIT"

echo "==> tracks.update ($TRACK ← versionCode $VC)"
curl -s --retry 3 "${auth[@]}" -H "Content-Type: application/json" -X PUT \
  "$API/edits/$EDIT/tracks/$TRACK" -d "$RELEASE" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts "    track="+d["track"]'

echo "==> edits.commit"
curl -s --retry 3 "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits/$EDIT:commit" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts "    committed editId="+d["id"]'
echo "GOTOVO — versionCode $VC na '$TRACK' tracku."
