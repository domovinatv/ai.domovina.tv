---
description: Predaj dogovoreni plan orkestratoru (planner → tim) u tmux timu ovog projekta
---

Ti si PLANNER (lijevi panel, `scripts/tim.sh`). Korisnik je s tobom dogovorio
posao i sad ga predaješ timu: orkestrator ga razbija na taskove za **dev1** i
**dev2**, a **reviewer** provjerava rezultat prije sljedećeg kruga.

Ne implementiraj ništa sam. Tvoj jedini output ovdje je **plan-dokument** i
**jedna poruka orkestratoru**.

## 1. Zapiši plan

Putanja: `docs/plans/YYYY-MM-DD-<kratki-slug>.md` (današnji datum; ako plan za
isti posao već postoji, dopuni ga umjesto novog fajla).

Predložak — drži se ovih naslova, orkestrator ih čita:

```markdown
# <Naslov posla>

## Cilj
Jedan odlomak: što korisnik dobiva kad je gotovo.

## Kontekst
Zatečeno stanje s dokazom u kodu (`file.dart:123`), odluke koje su već pale,
i sve što bi dev inače krivo pretpostavio.

## Taskovi

### T1 — <naziv>
- **Fajlovi**: točan popis (ovo je ugovor o izolaciji između devova)
- **Opis**: što napraviti
- **Definicija gotovog**: mjerljivo (što mora raditi / koji test prolazi)

### T2 — <naziv>
…

## Ovisnosti
Npr. `T1 → T2` (serijski), `T3 ‖ T4` (paralelno). Ako dva taska dijele fajl,
napiši to izrijekom — orkestrator ih tada NE smije poslati istovremeno.

## Rizik
`nizak` | `srednji` | `visok` + zašto. Visok = auth, plaćanja/pinka, Supabase
shema, `web/_worker.js`, RevenueCat, deploy putanja. Orkestrator na visokom
riziku diže reviewera na Opus.

## Verifikacija
Kako se dokazuje da radi: `flutter analyze`, ciljani testovi, ručna provjera
u appu (koja ruta, što se vidi).

## Van opsega
Što NAMJERNO ne diramo u ovom krugu.
```

Pravila pri pisanju plana:

1. **Fajlovi po tasku moraju biti disjunktni** za taskove koji smiju ići
   paralelno — dev1 i dev2 dijele isti radni direktorij (bez worktreeja, razlog
   u headeru `scripts/tim.sh`). Ako se preklapaju, spoji ih u jedan task ili ih
   označi kao serijske.
2. **Poznate zajedničke točke** koje ruše paralelizaciju: `lib/l10n/app_hr.arb`
   i `app_en.arb` (dira ih gotovo svaki UI task — sve i18n izmjene kruga daj
   JEDNOM devu), `web/_worker.js` (sve rute), `pubspec.yaml`, `CLAUDE.md`.
   Ako dva taska trebaju isti od tih fajlova, označi ih kao serijske.
3. **Task je veličine jednog konteksta** — ako ne stane u ~jedan `/clear`
   ciklus, razbij ga.
4. Ne prepisuj CLAUDE.md pravila u plan; devovi ih imaju.
5. Ako nešto nisi provjerio u kodu, napiši „**PROVJERITI:** …" umjesto da
   pogađaš — dev to onda tretira kao prvi korak taska, ne kao činjenicu.

## 2. Pošalji orkestratoru

```bash
./scripts/tim-send.sh orkestrator '/tim izvrši plan iz docs/plans/<fajl>.md'
```

Šalješ **putanju, ne sadržaj** (jedna linija; helper odbija višelinijske
poruke). Ako je posao samo dopuna već predanog plana, pošalji npr.
`'/tim dopuna: docs/plans/<fajl>.md — dodan T5, ostalo nepromijenjeno'`.

## 3. Javi korisniku

Kratko: koji plan je predan, koji taskovi idu paralelno a koji serijski, i kako
prati napredak:

- tmux status bar (dolje desno) — orkestrator ga osvježava
- `./scripts/tim-status.sh` — tko radi, tko čeka, verdikti reviewera
- `./scripts/tim-read.sh dev1 120` — što točno piše u nekom panelu

**Deploy i push NE radiš ti.** Ako korisnik ovdje kaže „deployaj", proslijedi
to orkestratoru (`./scripts/tim-send.sh orkestrator 'deployaj'`) i javi
korisniku da si delegirao. Razlog nije formalnost: `deploy.sh` mijenja praćene
fajlove (bump verzije u `pubspec.yaml` i `appVersion` u `lib/main.dart`), pa
ostavlja necommitane izmjene u zajedničkom radnom stablu — a integracija i
commit su orkestratorov posao. Uz to ti build output nepotrebno puni kontekst.

Zatim nastavljaš normalno raditi s korisnikom u ovom panelu (istraživanje,
sljedeći plan). **Dok tim radi ne diraš kod** — samo `docs/plans/*`.

## Posao za predaju

$ARGUMENTS
