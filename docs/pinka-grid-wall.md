# Pinka Grid Wall — 120×120 zid kvadratića na /c/:slug/doniraj

> Zapisano prije /clear Claude sesije koja je feature implementirala
> (2026-07-21). Kod: `lib/pinka_sdk/src/widgets/pinka_grid_wall.dart`,
> ožičenje u `pinka_campaign_screen.dart` + `pinka_contribute_panel.dart`.

## Što je to

Vizualni prikaz "donacijom kupuješ svoj kvadratić": 14.400 ćelija u 10
koncentričnih cjenovnih prstenova (rub 1 € → jezgra 1000 €). Faza 1 =
prezentacija + preselekcija iznosa; NEMA backend rezervacije ćelija.

## Porijeklo i odluke koje se ne vide iz koda

- **Portirano iz** `/Users/ms/git/spremni/za-sponzorstvo/pixel-grid-v1/`
  (samostojeći Flutter billboard-builder, lokalni git bez remotea, sve u
  `lib/main.dart`). Uzeti su `BillboardPainter` pristup (jedan paint pass),
  geometrija 10 prstenova i first-match-wins logika; izbačeni su expansion
  algoritmi, JSON/PNG export, sponsor SVG overlay i admin forma.
- **Cijene = original ÷ 10**, zaokruženo na 1/2/5 ljestvicu, da se vanjskih
  pet prstenova (1/2/5/10/20 €) točno poklopi s `_presetsCents` čipovima u
  `PinkaContributePanel`. Ako se ikad mijenjaju preset čipovi, uskladiti
  `_zones` u `pinka_grid_wall.dart`.
- **Prsten se računa O(1)** iz udaljenosti od ruba (`min(x, y, 119-x, 119-y)`
  vs `startLayer` pragovi `[0,3,6,10,14,19,25,32,41,51]`) umjesto linearnog
  `containsPoint` skena — identičan rezultat jer su prstenovi koncentrični.
- **Boje**: navy tint rampa `AppTheme.croBlue → +38 % white` (rub → jezgra),
  zauzete ćelije `cs.tertiary` (crvena), NIKAD `cs.primary` za brand-fill.
  Jezgra namjerno NIJE crvena da se zauzete ćelije uvijek vide.
- **JEZGRA verzalizacija**: ARB vrijednost je "Jezgra" (pravilo: bez
  ALL-CAPS u ARB-u), `.toUpperCase()` se radi u kodu pri gradnji liste
  naziva zona.

## Deterministički placement (faza 1, klijentski)

`pinka_finance.public_contributions` view NEMA koordinate, pa se doprinosi
mapiraju na klijentu:

1. kanonski sort po `id` (placement ne smije ovisiti o redoslijedu s API-ja),
2. najskuplji prsten čija je cijena ≤ `amountCents`,
3. FNV-1a(id) % broj ćelija prstena + linearni probe; pun prsten → prelijevanje
   u prvi jeftiniji.

Bez `Random()`/`DateTime.now()` — isti popis uvijek daje isti raspored.
`log()` javlja "mapirano N/M" + prelijevanja.

**TODO faza 2 (backend, domovina-api)**: prava rezervacija traži
`cell_x`/`cell_y` kolone u `contributions` + unique constraint. Dok toga
nema, NE tvrditi korisniku da je kvadratić "njegov" zauvijek. (U trenutku
pisanja u radnom stablu postoji necommitani `pinka_slot.dart` iz druge
sesije — moguće da faza 2 već kreće; provjeriti prije dupliranja posla.)

## Performanse (zašto je struktura takva kakva je)

- Baza (14.400 rectova) je iza `RepaintBoundary` i repainta se SAMO kad se
  promijeni potpis placement mape ili tema; hover/selekcija su zaseban
  overlay painter (max 2 strokea). Ne spajati ih "radi jednostavnosti".
- Hover radi `setState` samo na promjenu ćelije (`_setHover` guard), i to
  unutar `PinkaGridWall` State-a — ne rebuilda ekran.

## Gotchas otkriveni pri verifikaciji

- **`MouseRegion.onHover` NE okida na ulazak** pokazivača u regiju (samo na
  pomake unutar nje) — obavezno i `onEnter`, inače label/highlight kasne do
  prvog pomaka. Sintetički (automation) hover bez toga uopće ne radi.
- **Preset tick pattern**: panel prima `presetAmountCents` +
  `presetAmountTick`; tick se inkrementira na svaki tap da se ISTI iznos
  smije ponovno primijeniti (korisnik ručno promijeni iznos pa opet tapne
  istu zonu). `didUpdateWidget` uspoređuje tick, ne iznos.
- Preset iznosi (1–20 €) selektiraju čip i čiste "Ostalo"; veći iznosi se
  upisuju u "Ostalo" (`fmtEur`) da UI odražava odabir — čip je selektiran
  samo ako je `_customCtrl.text.isEmpty`.
- Snackbar predložak je `"{name} — iznos postavljen na {price} €."` BEZ
  prefiksa "Zona", jer nazivi zona već sadrže riječ "zona"
  ("Zona Poslovna zona" bug uhvaćen na živom testu).

## Verificirano (2026-07-21, lokalno, prod Supabase podaci)

`flutter analyze` čist; `localhost:5173/c/domovina-tv/doniraj`: render na
mobilnoj i desktop širini, tap centar → 1000 € u panel, tap rub → 1 € čip,
tap zauzeta ćelija → bottom sheet s donatorom, hover labeli rade, SEPA/
on-chain tok netaknut. Mapirano 38/38 doprinosa.
