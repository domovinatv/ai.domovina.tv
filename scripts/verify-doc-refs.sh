#!/usr/bin/env bash
# Provjeri da svaka putanja u kodu citirana u markdown dokumentu stvarno
# postoji. Nastalo iz konkretnog incidenta 14. 8. 2026.: AI-generirana analiza
# citirala je 33 putanje od kojih 6 nije postojalo na navedenom mjestu —
# imena datoteka točna, direktoriji izmišljeni. Takva greška prođe svaki
# letimičan pregled jer izgleda uvjerljivo.
#
#   ./scripts/verify-doc-refs.sh docs/*.md
#   ./scripts/verify-doc-refs.sh            # default: svi docs/**/*.md
#
# Izlazni kod 1 ako ijedna putanja fali, pa se može staviti u CI ili hook.
#
# Hvata SAMO putanje u backtickovima koje POČINJU poznatim korijenom repoa
# (lib/, test/, web/, scripts/, android/, ios/, macos/, assets/, docs/,
# .nightly/, .claude/). Namjerno NE hvata gole riječi, URL-ove ni putanje u
# sibling repoe (`../fetch.domovina.tv/…`) — cilj je nula lažnih uzbuna.
#
# Preskače se:
#   - putanje s `…` ili `{a,b}` (očito su placeholderi, ne stvarne datoteke)
#   - glob uzorci (`docs/splash-*.md`) — provjerava se da uzorak nešto MATCHA
#   - blokovi između <!-- doc-refs:ignore-start --> i <!-- doc-refs:ignore-end -->,
#     za dokumente koji NAMJERNO citiraju krive putanje (npr. tablica ispravaka)

set -uo pipefail
cd "$(dirname "$0")/.."

shopt -s globstar nullglob
files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  files=(docs/**/*.md)
fi

roots='lib|test|web|scripts|android|ios|macos|assets|docs|\.nightly|\.claude'
missing=0
checked=0
skipped=0

for doc in "${files[@]}"; do
  [ -f "$doc" ] || continue
  doc_header_printed=0
  ignoring=0
  declare -A seen=()

  while IFS= read -r line; do
    case "$line" in
      *'doc-refs:ignore-start'*) ignoring=1; continue ;;
      *'doc-refs:ignore-end'*)   ignoring=0; continue ;;
    esac
    [ $ignoring -eq 1 ] && continue

    # Svaki `backtick` isječak iz ovog retka.
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      # Mora POČETI korijenom repoa (ne hvata ../sibling/docs/x.md).
      [[ "$ref" =~ ^(${roots})/ ]] || continue
      # Placeholderi nisu putanje.
      case "$ref" in *'…'*|*'{'*|*' '*) skipped=$((skipped+1)); continue ;; esac
      ref="${ref%%[.,;:)]}"
      [ -n "${seen[$ref]:-}" ] && continue
      seen[$ref]=1
      checked=$((checked + 1))

      # Glob uzorak → dovoljno je da matcha bar jednu datoteku.
      if [[ "$ref" == *'*'* ]]; then
        matches=( $ref )
        [ ${#matches[@]} -gt 0 ] && continue
      elif [ -e "$ref" ]; then
        continue
      fi

      base=$(basename "$ref")
      hint=$(find lib test web scripts -name "$base" 2>/dev/null | head -3 | tr '\n' ' ')
      if [ $doc_header_printed -eq 0 ]; then
        printf '\n\033[1m%s\033[0m\n' "$doc"
        doc_header_printed=1
      fi
      if [ -n "$hint" ]; then
        printf '  \033[31mFALI\033[0m  %s\n        \033[33m→ postoji kao:\033[0m %s\n' "$ref" "$hint"
      else
        printf '  \033[31mFALI\033[0m  %s\n        \033[33m→ nema datoteke tog imena nigdje u repou\033[0m\n' "$ref"
      fi
      missing=$((missing + 1))
    done < <(grep -oE '`[^`]+`' <<< "$line" | tr -d '`')
  done < "$doc"
  unset seen
done

echo
if [ $missing -eq 0 ]; then
  printf '\033[32m✓\033[0m %d putanja provjereno (%d placeholdera preskočeno), sve postoje\n' \
    "$checked" "$skipped"
  exit 0
fi
printf '\033[31m✗\033[0m %d od %d putanja ne postoji\n' "$missing" "$checked"
exit 1
