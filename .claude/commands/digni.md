---
description: Pripremi kickoff za AI tim i daj korisniku komandu koju pokreće u svom iTerm prozoru
---

Korisnik želi pustiti novi posao AI timu (`scripts/tim.sh`, pet Claude Code
panela u tmuxu).

## ŽELJEZNO PRAVILO: prozore otvara ČOVJEK

**Nikad ne otvaraj, ne resizeaj i ne zatvaraj iTerm prozore.** Ni preko
`osascript`, ni preko `open -a`, ni na bilo koji drugi način. Odluka vlasnika,
8.8.2026.

Nije stvar ukusa — izmjereno je kako se lomi. Kad se ubije tmux session na koji
su prozori attachani, iTermov AppleScript se **trajno zablokira**
(`AppleEvent timed out -1712`, do restarta iTerma). U tom incidentu je stari
tim bio ubijen a novi se nije digao, jer je `osascript` stajao na kritičnom
putu. Puni popis zamki je u headeru `scripts/tim-kickoff.sh`.

Tvoj doprinos je **kickoff fajl i komanda**. Prozor i Enter su korisnikovi.

## Postupak

1. **Provjeri gdje si.** Ako je `$TMUX` postavljen, ti si panel unutar tima —
   ne pokrećeš ovo. Javi korisniku i stani.

2. **Sastavi kickoff.** Ako `$ARGUMENTS` nije prazan, to je prompt. Ako je
   prazan a iz razgovora je jasno što ide timu, sastavi sam: putanja do plana,
   koji taskovi idu u ovaj krug a koji NE, zamke koje moraju u definiciju
   gotovog. Ako nije jasno — pitaj.

3. **Zapiši ga** u `.tim/kickoff-prompt.md` (Write tool, ne skripta). Zaglavlje:

   ```markdown
   # Kickoff za planner — YYYY-MM-DD HH:MM

   Prvo se orijentiraj po `.claude/commands/pocni.md`, zatim izvrši ovo:

   ---

   <prompt>
   ```

   Višelinijski je u redu — planneru se šalje samo putanja, nikad sadržaj
   (TUI svaki `\n` čita kao submit).

4. **Provjeri stanje tima** (`./scripts/tim-status.sh`) i **javi korisniku
   komandu**, u bloku za kopiranje:

   ```bash
   cd /Users/ms/git/domovinatv/domovina.ai && ./scripts/tim-kickoff.sh --fresh
   ```

   Bez `--fresh` ako se treba attachati na postojeći tim. Uz komandu reci:
   otvori novi iTerm prozor (⌘N), zalijepi, ⌘+Enter za fullscreen.

5. **Ako tim treba ugasiti a paneli rade** — upozori što se gubi (kontekst
   orkestratora je često jedino mjesto gdje živi ops znanje) i predloži da mu
   prvo pošalješ nalog da to zapiše u `docs/`, pa onda `--fresh`.

## Što skripta radi kad je korisnik pokrene

- `--fresh` → `tim-kill.sh` (odbija gasiti zauzet tim), pa čisti mrtvi
  `.tim/panes.env` i `.tim/status.line`; verdikti u `.tim/reviews/` ostaju.
- Digne tim **headless** (`tim.sh` bez TTY-ja se ne attacha), pričeka session.
- Pričeka da planner TUI proradi, pa mu pošalje `Pročitaj … pa izvrši.`
- Na kraju `exec tmux attach` u prozoru u kojem je pokrenuta.

Ako `.tim/kickoff-prompt.md` postoji a prompt nije dan u argumentu, skripta
koristi taj fajl — zato je dovoljno da ti napišeš fajl, a korisnik pokrene
komandu bez argumenata.

## Granice

- **Drugi tim uz postojeći ne postoji kao opcija.** dev1/dev2 dijele radni
  direktorij, a orkestrator je jedini koji commita — dva orkestratora u istom
  stablu commitaju jedan drugome nedovršen rad. Paralelan rad ide kroz drugi
  REPO (session je `tim-<repo-slug>`).
- **Ako tim već radi, prompt se NE šalje** planneru (ondje korisnik tipka).
  Skripta ispiše komandu za ručno slanje.
- Ti smiješ slati poruke **orkestratoru/devovima/revieweru** kroz
  `tim-send.sh`; u planner samo `--force` i samo kad je panel dokazano prazan.

## Prompt za predaju

$ARGUMENTS
