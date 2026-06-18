#!/usr/bin/env bash
# Mobilni release build (Android AAB + iOS IPA) za store upload.
#
#   ./scripts/build-mobile-release.sh            # oba (AAB + IPA)
#   ./scripts/build-mobile-release.sh android    # samo AAB
#   ./scripts/build-mobile-release.sh ios        # samo IPA
#
# Embeda Supabase/Meili config preko --dart-define iz .env (isti princip kao
# scripts/deploy.sh za web). Android release zahtijeva android/key.properties
# (vidi android/app/build.gradle.kts) — bez njega build padne nazad na debug
# potpis koji Play odbija.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a; source .env; set +a
else
  echo "GRESKA: .env ne postoji — kopiraj .env.example u .env"; exit 1
fi

DEFINES=""
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  DEFINES="--dart-define=SUPABASE_URL=${SUPABASE_URL} --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
else
  echo "UPOZORENJE: SUPABASE_URL/ANON_KEY nije u .env — build ide bez Supabase integracije"
fi
[[ -n "${CERTILIA_SERVER_URL:-}" ]] && DEFINES="${DEFINES} --dart-define=CERTILIA_SERVER_URL=${CERTILIA_SERVER_URL}"
[[ -n "${MEILI_URL:-}" ]]          && DEFINES="${DEFINES} --dart-define=MEILI_URL=${MEILI_URL}"
[[ -n "${MEILI_SEARCH_KEY:-}" ]]   && DEFINES="${DEFINES} --dart-define=MEILI_SEARCH_KEY=${MEILI_SEARCH_KEY}"

TARGET="${1:-all}"

flutter pub get

if [[ "$TARGET" == "all" || "$TARGET" == "android" ]]; then
  if [[ ! -f android/key.properties ]]; then
    echo "GRESKA: android/key.properties ne postoji — release bi bio debug-potpisan (Play ga odbija)."; exit 1
  fi
  echo "==> Android App Bundle (AAB)…"
  flutter build appbundle --release $DEFINES
  echo "AAB: build/app/outputs/bundle/release/app-release.aab"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]]; then
  echo "==> iOS IPA…"
  flutter build ipa --release $DEFINES
  echo "IPA: build/ios/ipa/*.ipa"
fi

echo "Gotovo."
