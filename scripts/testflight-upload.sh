#!/usr/bin/env bash
# Upload IPA na TestFlight preko altool + ASC API key (simetrično play-upload.sh).
#   ./scripts/testflight-upload.sh
# Preduvjet: ./scripts/build-mobile-release.sh ios (IPA u build/ios/ipa/).
# altool sam nalazi .p8 u ~/.appstoreconnect/private_keys/ po key ID-u.
set -euo pipefail
cd "$(dirname "$0")/.."

ASC_KEY_ID="${ASC_KEY_ID:-25KYCN22QD}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de85-f7cc-47e3-e053-5b8c7c11a4d1}"

IPA=$(ls build/ios/ipa/*.ipa 2>/dev/null | head -1) || true
[[ -n "${IPA:-}" ]] || { echo "GRESKA: nema IPA u build/ios/ipa/ — pokreni ./scripts/build-mobile-release.sh ios"; exit 1; }

echo "==> altool --upload-app ($(du -h "$IPA" | cut -f1))"
xcrun altool --upload-app -f "$IPA" --type ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo "GOTOVO — build u obradi na App Store Connectu → TestFlight za ~5-15 min."
