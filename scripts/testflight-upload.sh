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
# altool na odbijenicu vrati exit 0 — jedini trag je tekst. Izmjereno 13.8. i
# 18.8.2026.: "UPLOAD FAILED with 2 errors" (409, zatvoren train 2.0.136), a
# nightly je javio ✅ i 45 min pollao build koji nikad nije stigao.
OUT="$(mktemp -t altool)"
trap 'rm -f "$OUT"' EXIT
rc=0
xcrun altool --upload-app -f "$IPA" --type ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$OUT" || rc=$?
if grep -q "Pre-Release Train" "$OUT"; then
  VER=$(grep -o "train version '[^']*'" "$OUT" | head -1)
  echo "GRESKA: Apple je zatvorio ${VER:-train ove verzije} — ta verzija je već odobrena."
  echo "        Bumpaj verziju u pubspec.yaml (./scripts/deploy.sh to radi) i ponovi."
  exit 3
fi
# Uspjeh se priznaje samo pozitivno — tišina ili nepoznat format nije uspjeh.
if [[ $rc -ne 0 ]] || grep -q "UPLOAD FAILED" "$OUT" || ! grep -q "UPLOAD SUCCEEDED" "$OUT"; then
  echo "GRESKA: altool upload nije prošao (exit $rc) — vidi ispis iznad."
  exit $(( rc ? rc : 2 ))
fi
echo "GOTOVO — build u obradi na App Store Connectu → TestFlight za ~5-15 min."
