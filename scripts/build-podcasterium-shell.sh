#!/usr/bin/env bash
# Tripwire za white-label granicu: izgradi Podcasterium ljusku
# (sestrinski repo ../../podcasterium/podcasterium-app) nad ZADANIM
# packages/podcast_core. Promjena jezgre koja makne export, preimenuje flag ili
# doda obvezno polje u BrandConfig pada OVDJE, u DOMOVINA-i, prije taga —
# vidi podcasterium-app/docs/08-white-label-architecture.md §5.
#
#   ./scripts/build-podcasterium-shell.sh [core-dir] [shell-dir]
#
# core-dir  zadano packages/podcast_core ovog repoa (nightly proslijedi svoj worktree)
# shell-dir zadano ../../podcasterium/podcasterium-app
#
# Ljuska se kopira u privremeni direktorij (bez build/, .dart_tool/) i tamo
# dobije pubspec_overrides.yaml koji pokazuje na core-dir, pa se vlasnikov
# checkout i njegov override NE diraju. Izlazni kod 2 = ljuska ne postoji
# (preskočeno), 1 = pad, 0 = analyze + test + build web prošli.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$(cd "${1:-$ROOT/packages/podcast_core}" && pwd)"
SHELL_SRC="${2:-$ROOT/../../podcasterium/podcasterium-app}"

if [[ ! -f "$SHELL_SRC/pubspec.yaml" ]]; then
  echo "podcasterium-app nije nađen na $SHELL_SRC — tripwire preskočen"
  exit 2
fi
SHELL_SRC="$(cd "$SHELL_SRC" && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/podcasterium-shell.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
rsync -a --exclude build --exclude .dart_tool --exclude .git \
  --exclude pubspec.lock --exclude pubspec_overrides.yaml \
  "$SHELL_SRC/" "$TMP/"
cat > "$TMP/pubspec_overrides.yaml" <<YAML
dependency_overrides:
  podcast_core:
    path: $CORE
YAML

echo "==> Podcasterium ljuska: $SHELL_SRC"
echo "==> podcast_core:        $CORE"
cd "$TMP"
flutter pub get
flutter analyze
flutter test
flutter build web
echo "==> Podcasterium ljuska prolazi nad $CORE"
