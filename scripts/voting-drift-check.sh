#!/usr/bin/env bash
# Tripwire: registar hrvatskih podcasta ↔ glasački bazen u bazi.
#
# `domovina_ai.vote_candidates` je SNIMKA `fetch.domovina.tv/data/podcasts_registry.json`,
# a ne živi pogled na njega — dodavanje podcasta u registar ne stigne do baze
# dok se ne pokrene `sync_voting_candidates.mjs --commit`. Izmjereno 25.8.2026.:
# registar je 17 dana nosio 37 kandidata (među njima AbbaCast) kojih u bazi nije
# bilo. Korisnici za njih jednostavno nisu mogli glasati, a ništa to nije javilo.
#
#   ./scripts/voting-drift-check.sh              # tiho kad je poravnato
#   ./scripts/voting-drift-check.sh --verbose    # uvijek ispiši izvještaj
#   ./scripts/voting-drift-check.sh --no-telegram
#   ./scripts/voting-drift-check.sh --sync       # na drift ODMAH pokreni --commit
#
# Pokreće ga launchd (vidi launchd/ai.domovina.voting-drift.plist), ali radi i ručno.
#
# Namjerno NE zove `--commit` sam od sebe u default modu: sync uploada avatare na
# CDN i mijenja `status` redova, pa je to promjena produkcijskih podataka koju
# potpisuje čovjek. Tripwire javlja, čovjek odlučuje. `--sync` je za slučaj kad
# se svjesno odluči da smije sam.
set -uo pipefail

export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
# launchd daje minimalan PATH — alate razriješi eksplicitno.
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/ruby/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# node živi pod nvm-om, a nvm se aktivira tek u interaktivnom shellu — pod
# launchdom ga NEMA (izmjereno 25.8.2026.: prvi kickstart pao s
# „node: command not found", exit 2). Verzija se ne hardkodira: uzmi najnoviju
# instaliranu, da nadogradnja node-a ne obori tripwire.
if ! command -v node >/dev/null 2>&1; then
  NVM_BIN="$(/bin/ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
  [[ -n "${NVM_BIN:-}" ]] && export PATH="$NVM_BIN:$PATH"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FETCH_REPO="${FETCH_REPO:-$HOME/git/domovinatv/fetch.domovina.tv}"
SYNC="$FETCH_REPO/sync_voting_candidates.mjs"

VERBOSE=0; TELEGRAM=1; AUTOSYNC=0
for a in "$@"; do
  case "$a" in
    --verbose)     VERBOSE=1 ;;
    --no-telegram) TELEGRAM=0 ;;
    --sync)        AUTOSYNC=1 ;;
    *) echo "Nepoznat flag: $a" >&2; exit 2 ;;
  esac
done

notify() {  # nikad ne obara skriptu — notifikacija je posljedica, ne uvjet
  [[ $TELEGRAM -eq 1 ]] || { echo "(telegram isključen)"; return 0; }
  printf '%s' "$1" | "$ROOT/scripts/telegram-notify.rb" || true
}

# Sve što ide u <pre> MORA kroz ovo: parse_mode=HTML bi `<` iz izvještaja pročitao
# kao tag i cijela poruka bi propala s 400 (ista zamka kao u nightly-build.sh).
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

if ! command -v node >/dev/null 2>&1; then
  echo "GRESKA: nema node u PATH-u" >&2
  notify "⚠️ <b>Glasanje — tripwire ne radi</b>
<code>node</code> nije u PATH-u (nvm se ne aktivira pod launchdom)."
  exit 2
fi

if [[ ! -f "$SYNC" ]]; then
  echo "GRESKA: nema $SYNC (postavi FETCH_REPO)" >&2
  notify "⚠️ <b>Glasanje — tripwire ne radi</b>
nema <code>sync_voting_candidates.mjs</code> na <code>$(printf '%s' "$SYNC" | esc)</code>"
  exit 2
fi

IZVJESTAJ="$(cd "$FETCH_REPO" && node "$SYNC" --check 2>&1)"
STATUS=$?

case $STATUS in
  0)
    [[ $VERBOSE -eq 1 ]] && echo "$IZVJESTAJ"
    exit 0
    ;;
  1)
    echo "$IZVJESTAJ"
    # Slugovi znaju biti dugački; Telegram poruku reže sam notifier na 3800 znakova.
    # Od retka „Registar:" do praznog reda prije zaključka — bez okvira od crtica.
    SAZETAK="$(printf '%s' "$IZVJESTAJ" | sed -n '/^  Registar:/,/^─\{10,\}$/p' | sed '$d' | sed 's/^  //' | esc)"
    if [[ $AUTOSYNC -eq 1 ]]; then
      notify "⚠️ <b>Glasanje — bazen zaostaje za registrom</b>
<pre>$SAZETAK</pre>
Pokrećem <code>--commit</code>…"
      if (cd "$FETCH_REPO" && node "$SYNC" --commit); then
        notify "✅ <b>Glasanje — bazen poravnat</b>
<code>sync_voting_candidates.mjs --commit</code> prošao."
      else
        notify "❌ <b>Glasanje — sync pao</b>
<code>--commit</code> nije prošao, bazen je i dalje u driftu."
        exit 2
      fi
    else
      notify "⚠️ <b>Glasanje — bazen zaostaje za registrom</b>
<pre>$SAZETAK</pre>
Pokreni u <code>fetch.domovina.tv</code>:
<code>node sync_voting_candidates.mjs --commit</code>"
    fi
    exit 1
    ;;
  *)
    echo "$IZVJESTAJ" >&2
    notify "❌ <b>Glasanje — provjera drifta pukla</b>
<pre>$(printf '%s' "$IZVJESTAJ" | tail -c 800 | esc)</pre>"
    exit 2
    ;;
esac
