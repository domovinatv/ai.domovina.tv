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
# RevenueCat publishable SDK keys — public by design (appl_…/goog_… ili test_…
# za TestStore QA). Bez njih mobile build radi, ali paywall purchase je no-op.
[[ -n "${RC_PUBLIC_SDK_KEY_IOS:-}" ]]     && DEFINES="${DEFINES} --dart-define=RC_PUBLIC_SDK_KEY_IOS=${RC_PUBLIC_SDK_KEY_IOS}"
[[ -n "${RC_PUBLIC_SDK_KEY_ANDROID:-}" ]] && DEFINES="${DEFINES} --dart-define=RC_PUBLIC_SDK_KEY_ANDROID=${RC_PUBLIC_SDK_KEY_ANDROID}"

TARGET="${1:-all}"

flutter pub get

# iOS ide PRIJE Androida kad se builda "all": iOS flow radi `flutter clean`
# (simulator ostaci → x86_64 u objective_c.framework → altool 409), a clean
# bi obrisao već izbuildani AAB.
if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]]; then
  # `flutter build ipa` pada na export koraku (ITalk cert nije u keychainu,
  # Apple ID nije u Xcodeu) — vozimo xcodebuild direktno s App Store Connect
  # API key autentikacijom koja programatski kreira cert + profil.
  # Vidi docs/mobile-release-pipeline.md.
  ASC_KEY_ID="${ASC_KEY_ID:-25KYCN22QD}"
  ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de85-f7cc-47e3-e053-5b8c7c11a4d1}"
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "GRESKA: nema ASC API key na $ASC_KEY_PATH"; exit 1
  fi
  echo "==> iOS: flutter clean + config-only…"
  flutter clean
  flutter pub get
  flutter build ios --config-only --release $DEFINES

  echo "==> iOS: xcodebuild archive (ASC API key signing)…"
  xcodebuild archive \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath build/ios/archive/Runner.xcarchive \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

  echo "==> iOS: exportArchive → IPA…"
  xcodebuild -exportArchive \
    -archivePath build/ios/archive/Runner.xcarchive \
    -exportPath build/ios/ipa \
    -exportOptionsPlist ios/ExportOptions.plist \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  echo "IPA: build/ios/ipa/*.ipa  (upload: ./scripts/testflight-upload.sh)"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "android" ]]; then
  if [[ ! -f android/key.properties ]]; then
    echo "GRESKA: android/key.properties ne postoji — release bi bio debug-potpisan (Play ga odbija)."; exit 1
  fi
  echo "==> Android App Bundle (AAB)…"
  flutter build appbundle --release $DEFINES
  echo "AAB: build/app/outputs/bundle/release/app-release.aab"
fi

echo "Gotovo."
