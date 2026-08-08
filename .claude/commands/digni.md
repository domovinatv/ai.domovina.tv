---
description: Otvori novi maksimiziran iTerm prozor, digni AI tim i posij mu kickoff prompt
---

Korisnik želi pokrenuti AI tim (`scripts/tim.sh`, pet Claude Code panela u
tmuxu) u **novom iTerm prozoru**, s prvim zadatkom već poslanim planneru.

Sav posao radi `scripts/tim-open.sh`. Ti si ovdje samo da proslijediš prompt i
javiš ishod — **ne piši vlastiti AppleScript i ne pozivaj `tim.sh` izravno.**

## Postupak

1. **Provjeri gdje si.** Ako je `$TMUX` postavljen, ti si već panel unutar
   tima — tada NE pokrećeš ovo. Javi korisniku da se tim diže izvana i stani.

2. **Ako korisnik nije dao prompt** (`$ARGUMENTS` prazan), a iz razgovora je
   jasno što treba predati timu, sastavi ga sam: putanja do plana + što
   orkestrator mora znati prije dispatcha. Ako nije jasno, pitaj — bolje
   jedno pitanje nego tim koji krene u krivo.

3. **Odluči treba li čist tim.** Ako session već radi (`./scripts/tim-status.sh`),
   bez `--fresh` se novi prozor samo attacha na njega i prompt se NE šalje.
   Za nov posao gotovo uvijek želiš `--fresh` — ali on **gasi svih pet panela
   i njihov kontekst**, pa prije toga provjeri da nijedan ne radi i **pitaj
   korisnika**, osim ako je već rekao „fresh/čist/novi tim".

4. **Pokreni**, s promptom kao JEDNIM argumentom u jednostrukim navodnicima:

   ```bash
   ./scripts/tim-open.sh --fresh 'Predaj timu … Plan: docs/plans/….md'
   ```

   Prompt smije biti višelinijski — skripta ga zapisuje u
   `.tim/kickoff-prompt.md` i planneru šalje samo putanju (Claude TUI svaki
   `\n` čita kao submit, pa se sadržaj nikad ne šalje kroz `send-keys`).

5. **Javi ishod** u dvije-tri rečenice: je li tim nov ili se prozor attachao na
   postojeći, je li prompt poslan, i kako se prati napredak
   (`./scripts/tim-status.sh`, tmux status bar dolje desno).

## Što skripta radi sama (ne dupliciraj)

- Provjeri macOS, iTerm2, `tmux`, `claude`, `scripts/tim.sh`, `$TMUX`.
- Otvori novi iTerm prozor i **maksimizira** ga na vidljivi okvir. Puni zaslon
  ostaje ⌘+Enter, ručno.
- Digne tim s `TIM_AUTOSTART=0` kad ima prompt (inače bi `/pocni` i naša
  poruka jurili jedno drugo); orijentacija je tada dio kickoff fajla.
- Pričeka da session postoji i da planner TUI proradi, pa pošalje jednu liniju.

## Granice

- **Ako session već postoji i nema `--fresh`, skripta NE šalje prompt** — samo
  otvori prozor koji se attacha, i ispiše komandu za ručno slanje. Tako je
  namjerno: u planner panel korisnik tipka i poruka bi mu upala usred prompta.
  Ne zaobilazi to s `--force` osim ako je korisnik izričito rekao da je panel
  prazan.
- **Drugi tim uz postojeći ne postoji kao opcija.** dev1/dev2 dijele radni
  direktorij, a orkestrator je jedini koji commita — dva orkestratora u istom
  stablu commitaju jedan drugome nedovršen rad. Za paralelan rad na drugom
  poslu koristi drugi REPO (session je `tim-<repo-slug>`), ne drugi tim ovdje.
- Ovo diže tim **za repo iz kojeg se poziva** (session `tim-<repo-slug>`). Za
  drugi projekt pokreni skriptu iz tog repoa, ne mijenjaj `TIM_SESSION`.
- `--dry-run` kao prvi argument ispiše što bi se dogodilo bez otvaranja
  prozora — koristi kad nisi siguran u stanje.

## Prompt za predaju

$ARGUMENTS
