#!/usr/bin/env bash
# Nightly store build — ako je bilo commitova od zadnjeg uspješnog builda, izgradi
# iOS + Android iz HEAD-a i pošalji ih na TestFlight i Play internal track.
# Rezultat ide u Telegram grupu. Pokreće ga launchd u 01:00 (vidi
# launchd/ai.domovina.nightly-build.plist), ali radi i ručno.
#
#   ./scripts/nightly-build.sh                 # normalan run (skip ako nema promjena)
#   ./scripts/nightly-build.sh --force         # gradi i bez novih commitova
#   ./scripts/nightly-build.sh --skip-upload   # gradi i testira, ne dira storeove
#   ./scripts/nightly-build.sh --no-telegram   # bez notifikacije
#
# Dizajn (puno obrazloženje: docs/nightly-build-pipeline.md):
#   * Gradi iz ODVOJENOG git worktreea na HEAD shi — nikad ne dira tvoj radni
#     direktorij i ne može pokupiti nedovršeni WIP koji leži u njemu u 01:00.
#   * Build broj = max(ASC, Play, pubspec) + 1 — pubspec se NE mijenja i ne
#     commita; kolizija s već uploadanim buildom je nemoguća.
#   * Testovi su TVRDA vrata: pad → nema uploada. Poznati padovi žive u
#     .nightly/test-baseline.txt i izuzeti su iz vrata (ali se i dalje vrte i
#     javljaju, da se primijeti kad prorade).
set -uo pipefail

# macOS /bin/bash je 3.2 (nema mapfile), a launchd plist tipično zove baš njega.
# Prebaci se na homebrew bash 5 prije nego išta drugo napravimo.
if [[ -z "${BASH_VERSINFO:-}" || ${BASH_VERSINFO[0]} -lt 4 ]]; then
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "${BASH_SOURCE[0]}" "$@"
  fi
  echo "GRESKA: treba bash >= 4 (brew install bash)"; exit 1
fi

# launchd daje minimalan PATH — sve alate razriješi eksplicitno.
export PATH="$HOME/fvm/default/bin:$HOME/google-cloud-sdk/bin:/opt/homebrew/bin:/opt/homebrew/opt/ruby/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/.nightly"
WT="${NIGHTLY_WORKTREE:-$(dirname "$ROOT")/.nightly-domovina}"
BASELINE="$STATE/test-baseline.txt"
LAST_SHA_FILE="$STATE/last-built-sha"
RUN_TS="$(date +%Y-%m-%d-%H%M)"
LOG="$STATE/logs/$RUN_TS.log"

FORCE=0; SKIP_UPLOAD=0; TELEGRAM=1
for arg in "$@"; do
  case "$arg" in
    --force)       FORCE=1 ;;
    --skip-upload) SKIP_UPLOAD=1 ;;
    --no-telegram) TELEGRAM=0 ;;
    --help|-h)     sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)             echo "nepoznat flag: $arg"; exit 2 ;;
  esac
done

mkdir -p "$STATE/logs" "$STATE/reports"
exec > >(tee -a "$LOG") 2>&1

TIMEOUT_BIN="$(command -v gtimeout || command -v timeout || true)"
[[ -z "$TIMEOUT_BIN" ]] && echo "UPOZORENJE: nema timeout(1) — koraci nemaju watchdog"

REPORT=()          # linije za Telegram/report
FAILED_STEP=""
START_TS=$SECONDS

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
dur() { printf '%d min %02d s' $(($1 / 60)) $(($1 % 60)); }
# `"${REPORT[@]}"` na praznom polju puca pod `set -u` — uvijek kroz ovo.
report_lines() { [[ ${#REPORT[@]} -eq 0 ]] || printf '%s\n' "${REPORT[@]}"; }

# ── lock ─────────────────────────────────────────────────────────────────────
LOCK="$STATE/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +360 2>/dev/null)" ]]; then
    echo "UPOZORENJE: lock stariji od 6 h — preuzimam ga."
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null || { echo "ne mogu uzeti lock"; exit 1; }
  else
    echo "Već traje nightly (ili ručni) build — izlazim."
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# ── notifikacija ─────────────────────────────────────────────────────────────
notify() {
  [[ $TELEGRAM -eq 1 ]] || { echo "(telegram isključen)"; return 0; }
  printf '%s' "$1" | "$ROOT/scripts/telegram-notify.rb" || true
}

finish_fail() {
  local step="$1" rc="$2"
  local tail_txt
  tail_txt="$(tail -c 1800 "$LOG" | esc)"
  local msg="🌙❌ <b>Nightly pao — ${step}</b>
<code>${SHA_SHORT:-?}</code> · ${SUBJECT_ESC:-?}
$(report_lines)
⏱️ $(dur $((SECONDS - START_TS))) · izlazni kod ${rc}
<pre>${tail_txt}</pre>
📄 log: <code>.nightly/logs/${RUN_TS}.log</code>"
  notify "$msg"
  write_report "PAO ($step)"
  exit 1
}

write_report() {
  local status="$1"
  {
    echo "# Nightly $RUN_TS — $status"
    echo
    echo "- commit: ${SHA_SHORT:-?} — ${SUBJECT:-?}"
    echo "- build: ${BUILD_NAME:-?} (${BN:-?})"
    report_lines | sed 's/<[^>]*>//g' | sed 's/^/- /'
    echo "- trajanje: $(dur $((SECONDS - START_TS)))"
    echo "- log: .nightly/logs/$RUN_TS.log"
  } > "$STATE/reports/$RUN_TS.md"
}

# step <naziv> <timeout_min> <cmd…>
step() {
  local name="$1" tmo="$2"; shift 2
  echo
  echo "############ KORAK: $name (timeout ${tmo} min) ############"
  local t0=$SECONDS rc=0
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" -k 30 "${tmo}m" "$@" || rc=$?
  else
    "$@" || rc=$?
  fi
  local el=$((SECONDS - t0))
  if [[ $rc -ne 0 ]]; then
    [[ $rc -eq 124 ]] && echo "!! korak '$name' prekinut watchdogom nakon ${tmo} min"
    REPORT+=("❌ ${name} — pao nakon $(dur $el)")
    return $rc
  fi
  REPORT+=("✅ ${name} — $(dur $el)")
  return 0
}

# ── 1. ima li novih commitova ────────────────────────────────────────────────
SHA="$(git -C "$ROOT" rev-parse "${NIGHTLY_REF:-HEAD}")"
SHA_SHORT="${SHA:0:7}"
SUBJECT="$(git -C "$ROOT" log -1 --format=%s "$SHA")"
SUBJECT_ESC="$(printf '%s' "$SUBJECT" | esc)"
LAST_SHA="$(cat "$LAST_SHA_FILE" 2>/dev/null || echo '')"

echo "=== nightly $RUN_TS · HEAD=$SHA_SHORT · zadnji izgrađen=${LAST_SHA:0:7} ==="
if [[ "$SHA" == "$LAST_SHA" && $FORCE -eq 0 ]]; then
  echo "Nema novih commitova — izlazim."
  # Poruka se šalje i na prazan dan: njezin IZOSTANAK je signal da je launchd crknuo.
  [[ "${NIGHTLY_QUIET_SKIP:-0}" == "1" ]] || \
    notify "🌙💤 <b>Nightly preskočen</b> — nema novih commitova od <code>$SHA_SHORT</code>."
  exit 0
fi

# ── 2. tvrdi preduvjeti (da build ne ode tiho degradiran) ────────────────────
[[ -f "$ROOT/.env" ]] || { echo "GRESKA: nema .env"; finish_fail "preduvjeti" 1; }
set -a; source "$ROOT/.env"; set +a
MISSING=()
for k in SUPABASE_URL SUPABASE_ANON_KEY RC_PUBLIC_SDK_KEY_IOS RC_PUBLIC_SDK_KEY_ANDROID; do
  [[ -n "${!k:-}" ]] || MISSING+=("$k")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "GRESKA: u .env nedostaje: ${MISSING[*]}"
  REPORT+=("❌ .env nepotpun: ${MISSING[*]}")
  finish_fail "preduvjeti (.env)" 1
fi
[[ -f "$ROOT/android/key.properties" ]] || { echo "GRESKA: nema android/key.properties"; finish_fail "preduvjeti" 1; }

# ── 2b. disk ─────────────────────────────────────────────────────────────────
# Pun disk se NE prijavi kao "nema mjesta": Gradle javi "Failed to release lock"
# i "Could not add entry to cache", što izgleda kao pokvaren build. Izmjereno
# 2026-08-13 — boot volumen na 3 GiB je oborio AAB nakon 3 min. Provjeri unaprijed.
free_gb() { df -g "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }
MIN_FREE_BOOT="${NIGHTLY_MIN_FREE_BOOT_GB:-20}"
MIN_FREE_DD="${NIGHTLY_MIN_FREE_DD_GB:-15}"

BOOT_FREE="$(free_gb "$HOME")"
if [[ -z "$BOOT_FREE" || "$BOOT_FREE" -lt "$MIN_FREE_BOOT" ]]; then
  echo "GRESKA: na boot volumenu je ${BOOT_FREE:-?} GB slobodno (minimum ${MIN_FREE_BOOT} GB)."
  REPORT+=("❌ disk: boot volumen ${BOOT_FREE:-?} GB slobodno (< ${MIN_FREE_BOOT} GB)")
  finish_fail "preduvjeti (disk)" 1
fi

# Xcode DerivedData ovdje živi na vanjskom disku; ako nije montiran, xcodebuild
# padne s 2000 redaka ispisa koji nigdje ne kažu "nema diska".
DD_LOC="$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null || true)"
if [[ -n "$DD_LOC" ]]; then
  if [[ ! -d "$DD_LOC" ]]; then
    echo "GRESKA: Xcode DerivedData '$DD_LOC' ne postoji — disk nije montiran?"
    REPORT+=("❌ disk: DerivedData nedostupan ($DD_LOC)")
    finish_fail "preduvjeti (DerivedData disk)" 1
  fi
  DD_FREE="$(free_gb "$DD_LOC")"
  if [[ -z "$DD_FREE" || "$DD_FREE" -lt "$MIN_FREE_DD" ]]; then
    echo "GRESKA: na DerivedData volumenu je ${DD_FREE:-?} GB slobodno (minimum ${MIN_FREE_DD} GB)."
    REPORT+=("❌ disk: DerivedData volumen ${DD_FREE:-?} GB slobodno (< ${MIN_FREE_DD} GB)")
    finish_fail "preduvjeti (DerivedData prostor)" 1
  fi
  echo "==> disk: boot ${BOOT_FREE} GB · DerivedData ${DD_FREE} GB slobodno"
else
  echo "==> disk: boot ${BOOT_FREE} GB slobodno (DerivedData je na default lokaciji)"
fi

# Gradle cache (14 GB i raste) živi na vanjskom disku zajedno s DerivedData —
# boot volumen je pretijesan. ~/.gradle je simlink onamo, ali nightly postavlja
# GRADLE_USER_HOME eksplicitno da ne ovisi o simlinku.
BUILD_FILES="${NIGHTLY_BUILD_FILES:-/Volumes/DOMOVINA_BUILD}"
SPARSEBUNDLE="${NIGHTLY_SPARSEBUNDLE:-/Volumes/DOMOVINA2TB/domovina_ai_build_files/DOMOVINA_BUILD.sparsebundle}"
# Build artefakti žive u APFS sparsebundleu NA vanjskom disku, ne izravno na
# njemu: exFAT ondje ima alokacijski blok od 512 KB, pa je Gradle cache od 156 000
# sitnih datoteka narastao 14 GB → 41 GB. APFS unutra ima 4 KB blokove.
# Kontejner se montira sam — nightly ne smije ovisiti o tome da ga netko ručno digne.
if [[ ! -d "$BUILD_FILES" && -d "$SPARSEBUNDLE" ]]; then
  echo "==> montiram $SPARSEBUNDLE"
  hdiutil attach -nobrowse "$SPARSEBUNDLE" >/dev/null 2>&1 || {
    REPORT+=("❌ disk: ne mogu montirati $SPARSEBUNDLE")
    finish_fail "preduvjeti (montiranje build kontejnera)" 1
  }
fi
if [[ -d "$BUILD_FILES/gradle" ]]; then
  export GRADLE_USER_HOME="$BUILD_FILES/gradle"
  BF_FREE="$(free_gb "$BUILD_FILES")"
  if [[ -z "$BF_FREE" || "$BF_FREE" -lt "$MIN_FREE_DD" ]]; then
    echo "GRESKA: na ${BUILD_FILES} je ${BF_FREE:-?} GB slobodno (minimum ${MIN_FREE_DD} GB)."
    REPORT+=("❌ disk: build-files volumen ${BF_FREE:-?} GB slobodno")
    finish_fail "preduvjeti (build-files prostor)" 1
  fi
  echo "==> GRADLE_USER_HOME=$GRADLE_USER_HOME (${BF_FREE} GB slobodno)"

  # Xcode artefakti na predvidivoj putanji (inače Runner-<hash> po putanji projekta,
  # koji nitko ne čisti — zatečeno 66 GB naslaga). GC kad disk postane tijesan:
  # jedna arhiva traži desetke GB, a `flutter clean` svejedno gradi iznova.
  export BUILD_DERIVED_DATA="$BUILD_FILES/derived-data"
  if [[ -d "$BUILD_DERIVED_DATA" && "$BF_FREE" -lt "${NIGHTLY_DD_GC_GB:-60}" ]]; then
    echo "==> GC: brišem $BUILD_DERIVED_DATA ($(du -sh "$BUILD_DERIVED_DATA" 2>/dev/null | cut -f1)) jer je slobodno samo ${BF_FREE} GB"
    rm -rf "$BUILD_DERIVED_DATA"
    REPORT+=("🧹 GC: DerivedData obrisan (bilo ${BF_FREE} GB slobodno)")
  fi
elif [[ -L "$HOME/.gradle" && ! -e "$HOME/.gradle" ]]; then
  echo "GRESKA: ~/.gradle je slomljen simlink — vanjski disk nije montiran."
  REPORT+=("❌ disk: ~/.gradle simlink pokazuje u prazno")
  finish_fail "preduvjeti (Gradle cache disk)" 1
fi

# ── 3. izolirani worktree na HEAD shi ────────────────────────────────────────
if ! git -C "$ROOT" worktree list --porcelain | grep -qx "worktree $WT"; then
  echo "==> kreiram worktree $WT"
  rm -rf "$WT"
  git -C "$ROOT" worktree add --detach "$WT" "$SHA" || finish_fail "worktree" 1
else
  echo "==> osvježavam worktree na $SHA_SHORT"
  git -C "$WT" checkout --detach --force "$SHA" || finish_fail "worktree" 1
  # bez -x: ignorirani artefakti (build/, .dart_tool/, .env, key.properties) ostaju
  git -C "$WT" clean -fd >/dev/null
fi
ln -sfn "$ROOT/.env" "$WT/.env"
ln -sfn "$ROOT/android/key.properties" "$WT/android/key.properties"

cd "$WT"

# ── 4. analyze + testovi (tvrda vrata) ───────────────────────────────────────
step "pub get" 10 flutter pub get || finish_fail "pub get" $?
step "flutter analyze" 10 flutter analyze || finish_fail "flutter analyze" $?

mapfile -t ALL_TESTS < <(find test -name '*_test.dart' | sort)
BASE_TESTS=(); GATED_TESTS=()
if [[ -f "$BASELINE" ]]; then
  mapfile -t BASE_TESTS < <(grep -vE '^\s*(#|$)' "$BASELINE" | tr -d '\r')
fi
for t in "${ALL_TESTS[@]}"; do
  skip=0
  if [[ ${#BASE_TESTS[@]} -gt 0 ]]; then
    for b in "${BASE_TESTS[@]}"; do [[ "$t" == "$b" ]] && skip=1; done
  fi
  [[ $skip -eq 0 ]] && GATED_TESTS+=("$t")
done
echo "testovi u vratima: ${#GATED_TESTS[@]} · baseline (izuzeti): ${#BASE_TESTS[@]}"

step "testovi (${#GATED_TESTS[@]} fajlova)" 25 flutter test "${GATED_TESTS[@]}" \
  || finish_fail "testovi" $?

# Baseline se i dalje vrti — informativno. Ako prorade, javi da ih se makne.
if [[ ${#BASE_TESTS[@]} -gt 0 ]]; then
  if flutter test "${BASE_TESTS[@]}" >/dev/null 2>&1; then
    REPORT+=("🎉 baseline testovi sad PROLAZE — makni ih iz .nightly/test-baseline.txt")
  else
    REPORT+=("➖ baseline: ${#BASE_TESTS[@]} poznato crvenih (izuzeti iz vrata)")
  fi
fi

# ── 5. build broj ────────────────────────────────────────────────────────────
BUILD_NAME="$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)"
PUB_BUILD="$(grep '^version:' pubspec.yaml | sed 's/.*+//')"
STORE_MAX="$("$ROOT/scripts/store-status.rb" --max-build 2>/dev/null || echo 0)"
BN=$(( (STORE_MAX > PUB_BUILD ? STORE_MAX : PUB_BUILD) + 1 ))
echo "==> verzija ${BUILD_NAME} · build ${BN} (store max ${STORE_MAX}, pubspec ${PUB_BUILD})"
export BUILD_NUMBER="$BN"

# ── 6. build ─────────────────────────────────────────────────────────────────
step "iOS build (IPA)"     60 ./scripts/build-mobile-release.sh ios     || finish_fail "iOS build" $?
# IPA je izvezen (dSYM-ovi su otišli s uploadSymbols) — arhiva je samo balast.
rm -rf build/ios/archive
step "Android build (AAB)" 30 ./scripts/build-mobile-release.sh android || finish_fail "Android build" $?

if [[ $SKIP_UPLOAD -eq 1 ]]; then
  REPORT+=("⏭️ upload preskočen (--skip-upload)")
  notify "🌙🔧 <b>Nightly build OK (bez uploada)</b> ${BUILD_NAME} (${BN})
<code>$SHA_SHORT</code> · ${SUBJECT_ESC}
$(report_lines)
⏱️ $(dur $((SECONDS - START_TS)))"
  write_report "OK (bez uploada)"
  exit 0
fi

# ── 7. upload ────────────────────────────────────────────────────────────────
step "TestFlight upload"   30 ./scripts/testflight-upload.sh    || finish_fail "TestFlight upload" $?
step "Play internal upload" 20 ./scripts/play-upload.sh internal || finish_fail "Play upload" $?

# ── 8. verifikacija (upload 200 ≠ build je dobar) ────────────────────────────
# Apple obrađuje asinkrono; ITMS odbijenice stižu tek ovdje, ne na uploadu.
# Prozor: izmjereno 2026-08-13 da build ni 25 min nakon uploada još nije bio
# vidljiv u /v1/builds. 20 min je davalo lažni ⚠️ gotovo svaku noć.
IOS_STATE="PROCESSING"
for _ in $(seq 1 "${NIGHTLY_TF_POLL_MIN:-45}"); do
  sleep 60
  IOS_STATE="$("$ROOT/scripts/store-status.rb" --json 2>/dev/null \
    | ruby -rjson -e 'd=JSON.parse(STDIN.read); b=(d.dig("ios","builds")||[]).find{|x| x["build"].to_i==ARGV[0].to_i}; puts(b ? b["processing"] : "PROCESSING")' "$BN" \
    || echo PROCESSING)"
  echo "    TestFlight build $BN: $IOS_STATE"
  [[ "$IOS_STATE" == "VALID" || "$IOS_STATE" == "INVALID" || "$IOS_STATE" == "FAILED" ]] && break
done
case "$IOS_STATE" in
  VALID)   REPORT+=("🍏 TestFlight build ${BN}: VALID") ;;
  PROCESSING) REPORT+=("🍏 TestFlight build ${BN}: Apple ga još obrađuje (>${NIGHTLY_TF_POLL_MIN:-45} min) — nije greška, provjeri ujutro sa store-status.rb") ;;
  *)       REPORT+=("🍏❌ TestFlight build ${BN}: ${IOS_STATE}") ;;
esac

PLAY_OK="$("$ROOT/scripts/store-status.rb" --json 2>/dev/null \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); t=(d.dig("play","tracks")||[]).find{|x| x["track"]=="internal"}; puts((t&&t["releases"].any?{|r| r["codes"].include?(ARGV[0])}) ? "da" : "ne")' "$BN" \
  || echo '?')"
[[ "$PLAY_OK" == "da" ]] && REPORT+=("🤖 Play internal: versionCode ${BN} potvrđen") \
                         || REPORT+=("🤖⚠️ Play internal: versionCode ${BN} NIJE potvrđen čitanjem")

# ── 9. gotovo ────────────────────────────────────────────────────────────────
echo "$SHA" > "$LAST_SHA_FILE"
ICON="🌙✅"; [[ "$IOS_STATE" == "VALID" && "$PLAY_OK" == "da" ]] || ICON="🌙⚠️"
notify "${ICON} <b>Nightly ${BUILD_NAME} (${BN})</b>
<code>$SHA_SHORT</code> · ${SUBJECT_ESC}
$(report_lines)
⏱️ ukupno $(dur $((SECONDS - START_TS)))"
write_report "OK"
echo "=== gotovo: $(dur $((SECONDS - START_TS))) ==="
