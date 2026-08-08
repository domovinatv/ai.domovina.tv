# Zid podrške — redizajn ekrana `/c/:slug/support`

> Status: **plan, NE za predaju timu.** Tim trenutno radi na glasanju
> (`2026-08-08-glasanje-predaja.md`) i dijeli s ovim poslom `lib/l10n/app_*.arb`
> i `web/_worker.js`. Predaja tek kad taj krug bude integriran i commitan.

Ekran je funkcionalan, ali izgleda kao da su tri odvojena proizvoda zalijepljena
jedan do drugog. Ovaj dokument je dijagnoza po točkama koje si nabrojao, s
dokazom u kodu, pa prijedlog nove informacijske arhitekture.

---

## 1. Dijagnoza

### 1.1 URL u polju „Ime i prezime" nikad ne dobije karticu

**Uzrok, `domovina-api/supabase/functions/pinka-webhook/index.ts:110`:**

```ts
if (!row?.id || !row.message || row.link_preview) return; // no msg / already enriched
```

OG preview se dohvaća **isključivo iz `message`**. Igor je `hobba.io` upisao u
`display_name` → webhook je odustao prije nego je išta pogledao.

Ali to nije Igorova greška nego naša. On je htio da mu se na zidu vidi **brand**,
a mi mu nudimo polje koje se zove „Ime ili nadimak". Zid podrške *jest* sponzorski
zid — ljudi na njega stavljaju firmu, projekt, udrugu. Rješenje nije bolje
parsiranje imena, nego **treće polje koje ta namjera zaslužuje** (§2.4).

### 1.2 Dva polja bez oznake

`pinka_contribute_panel.dart:604` i `:630` — oba `TextField` imaju samo
`hintText`, nijedan `labelText`:

```dart
decoration: InputDecoration(isDense: true, counterText: '', hintText: l.pinkaNameHint),
```

Tekst u ARB-u je zapravo dobar („Ime ili nadimak (neobavezno)", „Poruka uz podršku
(neobavezno)"), **ali `hintText` nestaje čim korisnik utipka prvi znak**. Nakon
toga na ekranu stoje dva vizualno identična dense polja bez ijedne oznake. Uz to
su oba `isDense` i bez razmaka među sobom, pa čitaju kao jedno polje u dva reda.

### 1.3 Rupe u `Wrap` layoutu

`pinka_wall_list.dart:32` — `Wrap` s `maxWidth: 340` po kartici. `Wrap` slaže
redove i **poravnava ih po najvišoj kartici u redu**; kartica s poveznicom je
~3× viša od gole „Anoniman 1 €". Rupe na screenshotu su točno to.

Dodatno pogoršanje na istoj kartici (`:97–108`): URL se renderira **dvaput** —
jednom kao crveni linkificirani tekst iz poruke, pa odmah ispod kao preview
kartica s istim naslovom. Pola vertikalnog šuma je duplikat.

### 1.4 og:image — nije bug, nego namjerna odluka koju treba nadograditi

Ovo je najvažniji nalaz. `pay.domovina.ai/backend/src/og/preview.ts:80`:

```ts
image, // stored but the wall doesn't render remote images in v1 (IP-leak)
```

Slika **se dohvaća i sprema** (`PinkaLinkPreview.image` postoji u modelu,
`link_preview.image` u bazi), ali je `_LinkPreviewCard` namjerno **ne renderira**
— jer bi `Image.network` na proizvoljan tuđi host odao IP svakog posjetitelja
zida vlasniku tog hosta.

To je ispravna odluka i **ne smije se poništiti** tako da se jednostavno doda
`Image.network(p.image!)`. Facebook, WhatsApp i Slack rješavaju isto tako da
sliku **proxyjaju i keširaju kod sebe**. To je i naš put (§2.5) — a kod nas
ista slika postaje i tekstura zauzetog kvadratića (§2.2c).

Napomena uz drugo moguće čitanje tvoje točke 4: ako si mislio na to da naš
**vlastiti** `/c/:slug/support` link nema sliku pri dijeljenju u WhatsApp —
to je već implementirano, `web/_worker.js:1208` injecta OG + `DonateAction`
JSON-LD za obje rute i canonical je uvijek `/doniraj`. Provjerivo s
`node scripts/test-social-tags.mjs`.

### 1.5 Kvadratići i kartice su dva odvojena svijeta

`PinkaPublicContribution` (model, 44 linije) nema **nijedno** polje o mjestu na
mapi. `PinkaSlot` nema id doprinosa. Zid i mapa se pune iz dva različita izvora
(`public_contributions` i `public_slots`) i nemaju zajednički ključ — pa se
crveni kvadratić i kartica ne mogu povezati ni u jednom smjeru.

**Dobra vijest**: ključ u bazi već postoji.
`20260722120000_pinka_slots.sql:195` dodaje
`contributions.desired_slot_keys text[]`. Treba ga samo izložiti u
`public_contributions` viewu i dodati `contribution_id` u `public_slots`.
Nema nove logike, samo dva stupca u dva viewa.

### 1.6 Hijerarhija je obrnuta

Iz `pinka_campaign_screen.dart:495–553`, desktop je tri stupca u fiksnom
viewportu (stranica se **ne** scrolla, zid scrolla interno). Posljedice vidljive
na screenshotu:

- Naslov **„Zid podrške" stoji dvaput** — u app baru i kao naslov lijevog stupca.
- **„Podrži DOMOVINA podcast"** — jedina rečenica koja objašnjava *što je ovo* —
  nalazi se u desnom railu **ispod** mape kvadratića. Posjetitelj prvo vidi
  zagonetni piksel-grid, pa tek onda saznaje čemu služi.
- Tri stupca se natječu za pažnju bez ijednog primarnog poziva na akciju.
- Na mobitelu (`:474`) je redoslijed stats → grid → panel → main, s komentarom
  „posjetitelj prvo vidi ŠTO kupuje" — ali ne vidi, jer ne zna **zašto**.

Sve crveno na jednom ekranu (iznosi, linkovi, kvadratići) dodatno briše
hijerarhiju — ništa nije istaknuto jer je sve istaknuto.

---

## 2. Prijedlog

### 2.1 Treba li ovo izgledati kao stranica za prodaju ulaznica?

**Struktura da, metafora ne.**

Rastavio sam `events.sportify-app.com/e/mpt-vukovar-2908`. Redoslijed je:

```
hero (naziv, datum·vrijeme, lokacija, ODBROJAVANJE)
 → sidrene kartice: Ulaznice | Informacije | Lokacija | FAQ
 → "Odaberi ulaznice": redovi tiera (naziv, cijena "po ulaznici", stepper −/0/+)
 → VIP stolovi kao POSEBAN tier → "Odaberi stol na karti dvorane"
 → ljepljiva traka: "0 ulaznica · Ukupno 0,00 € · naknade uključene"
                    + CTA "Nastavi na plaćanje" + Visa/MC/Maestro
                    + sitno: "Ulaznice dolaze e-mailom · najviše 10 po narudžbi"
 → priča o kampanji + "Pročitaj više"
 → 4 imenovana citata (gradonačelnik, suorganizator, provincijal, izvođač)
 → Informacije (ulaz 17:00, kako do lokacije, kako stiže ulaznica)
 → Organizator + OIB + e-mail + Uvjeti kupnje + FAQ akordeon
```

Što **uzimamo**:

1. **Jedan primarni tok, sve ostalo ispod njega.**
2. **Ljepljiva traka sa sažetkom odabira i CTA-om** koja prati scroll.
3. **Sidrene kartice** za dugu stranicu.
4. **Blok povjerenja na dnu**: tko prima novac, OIB, kontakt, uvjeti.
5. **Imenovani citati kao društveni dokaz** — kod nas: poruke podržavatelja s
   najviše sadržaja, izdvojene iznad zida.

Što **ne uzimamo** iako je primamljivo:

- **Mapu kao „jedan od tiera".** Sportify VIP stolove nudi kao četvrtu opciju
  ispod Partera i Fan Pita, i to je za njih ispravno — karta dvorane im je
  logistički detalj, a ne razlog zašto netko dolazi na stranicu. **Kod nas je
  obrnuto: mreža 120×120 JE proizvod i prepoznatljiv element** (odluka
  vlasnika, 8.8.2026.). Degradirati je u tier značilo bi baciti jedino po čemu
  se ovaj ekran razlikuje od svakog drugog donate gumba na internetu.
- **Košaricu i „naknade uključene".** Ulaznica je kupnja s isporukom; donacija je
  dar s priznanjem. Čim se pojavi „Ukupno", ekran obećava protuuslugu koju nemamo.
- **Odbrojavanje**, osim ako kampanja stvarno ima rok. Lažni tajmer na donaciji
  je manipulacija.
- **Redoslijed „akcija prije priče".** Ticketing stranica smije staviti košaricu
  na vrh jer je posjetitelj **već odlučio** kad je kliknuo. Kod nas posjetitelj
  najčešće dolazi sa share linka i ne zna ništa — pa priča ide prva, a akcija
  ostaje dohvatljiva stalno (ljepljiva traka).

### 2.2 Mreža je identitet — nedostaje joj ono što je port izbacio

**Ispravak ranije verzije ovog dokumenta**: napisao sam da prodajemo 1×1
kvadratić i da je zato zauzeti kvadratić (~2,8 px na 340 px širine) nečitljiv.
To je kriva dijagnoza — **ne prodajemo 1×1**. Vektor sponzora se automatski širi
na slobodne susjedne kvadratiće, pa zauzeto područje raste do veličine na kojoj
je logo čitljiv. 120×120 je namjerno odabran balans, i to je odluka koja je pala
davno prije ovog dokumenta.

Prava dijagnoza je uža i lakša: **ta sposobnost postoji u kodu, ali nije
portirana.** Doslovno je zapisana u `docs/pinka-grid-wall.md:16`:

> Portirano iz `/Users/ms/git/spremni/za-sponzorstvo/pixel-grid-v1/` … Uzeti su
> `BillboardPainter` pristup (jedan paint pass), geometrija 10 prstenova i
> first-match-wins logika; **izbačeni su expansion algoritmi, JSON/PNG export,
> sponsor SVG overlay i admin forma.**

#### Gdje je izvornik

`/Users/ms/git/spremni/za-sponzorstvo/pixel-grid-v1/` — samostojeći Flutter
„Digital Billboard Builder", lokalni git **bez remotea**, sve u `lib/main.dart`
(2601 linija). Spec iz kojeg je nastao: `DREAMFLOW_PROMPT.md` u istom repou.

Relevantni dijelovi (`lib/main.dart`):

| Što | Gdje |
|---|---|
| `sponsorId → SVG URL` mapa | `_sponsorSvgUrls`, `:188` |
| `"x,y" → sponsorId` za **sve** ćelije pravokutnika | `:190` |
| Weight-based algoritam širenja | `_expandSponsors()`, `:500` |
| Provjera preklapanja pri širenju | `_canExpandToRect` `:747`, `_canExpandToRectClamped` `:767` |
| Tri načina širenja | `_expansionMode`, `:169` — `0` proporcionalno, `1` maksimalno (širi dok se svi ne dodirnu), `2` minimalno (samo kupljeni pikseli) |
| Prebacivanje 16:9 ↔ pojedinačni pikseli | `_showExpandedView`, `:168` |
| Render omjer | `AspectRatio(16/9)`, `:1755` |
| Dijalog za unos SVG-a | `_showSvgUrlDialog()`, `:970` |

Git povijest tog repoa je zapravo dnevnik razvoja algoritma:
`206ae95 feat: add maximum expansion mode toggle` → `01f9fa0 feat: three
expansion modes with cycling toggle` → `b6d5b73 fix: max expansion algorithm now
fills grid until all rectangles touch` → `499ac1c feat: heatmap zones with 10
concentric rings`. Zadnji commit (`4c50d49`) dodaje Thompson i HNS Family kao
testne sponzore; u kodu je 12 stvarnih logotipa (Aircash, Croatisimo,
Electrocoin, Entrio, Hrvatska pošta, Kodex, Pevex, Sofascore, Trendex,
VolimVodu…) s Firebase Storage URL-ova.

**Repo nema remote — postoji samo na ovom disku.** Prije nego se išta odatle
vadi, treba ga gurnuti na GitHub ili barem uvući u `domovina-storage`, inače je
jedan `rm -rf` udaljen od nestanka.

#### Što iz toga vraćamo

**(a) Širenje vektora na slobodne susjede** — `_expandSponsors()` i dvije
`_canExpand*` provjere. To je jedini pravi popravak čitljivosti; sve ostalo je
kozmetika oko njega. Kod postoji i radi, treba ga prilagoditi na naš
`slots`/`zones` model umjesto na `ReservedCell`.

**(b) Omjer kao parametar rendera, ne kao podatak.** Izvornik već crta 120×120
logičkih ćelija u `AspectRatio(16/9)`. Isti podaci daju 1:1, 16:9 i 9:16 —
vektor se regenerira, ništa se ne reže. Kod nas to znači da mreža može biti
kvadrat u heroju, 16:9 na dijeljenoj OG slici i 9:16 na mobilnom punom zaslonu,
**bez ijedne izmjene u bazi**.

**(c) Način širenja kao stanje prikaza.** Tri načina iz izvornika nisu debug
igračka nego tri odgovora na „kako zid izgleda dok je prazan": `minimalno`
pokazuje istinu (46 mrlja), `proporcionalno` je pošten kompromis,
`maksimalno` daje pun, reprezentativan zid od prvog dana. Za javni ekran
predlažem **proporcionalno**, s `maksimalno` rezerviranim za OG sliku i press
materijale — ali to je tvoja odluka (§3).

**(d) Natpis koji mrežu pretvara u razumljiv objekt.** Jedna rečenica iznad
mreže, ne ispod nje: *„14.400 kvadratića. 46 zauzeto. Uzmi svoj."* Mreža je
ujedno i mjerač napretka — zauzeta površina **jest** progress bar, pa zaseban
`▓▓▓░░░` widget ispada, a brojke postaju njezin potpis.

**(e) Zumiranje** ostaje korisno i uz širenje, ali kao sekundarno: pregled →
puni zaslon (na kojem, kako si rekao, jedan sponzor može zauzeti cijeli ekran).

Presedan za priču prema van i dalje je **Million Dollar Homepage** (Alex Tew,
2005., 1000×1000 piksela po dolaru, sve prodano, ~1,04 mil. USD) — s tim da je
naša verzija tehnički bolja upravo u ovome: Tew je tražio da kupac sam pošalje
sliku točne veličine bloka, a kod nas se vektor sam raširi i regenerira.

#### Zamka koja može srušiti cijeli (a): `flutter_svg` na webu

CLAUDE.md ima izričito pravilo: *„`flutter_svg` (`SvgPicture.asset`) causes
`Uncaught Error` on web builds. Rule: koristi PNG (`Image.asset`) umjesto SVG."*
Izvornik `pixel-grid-v1` koristi `flutter_svg` (`lib/main.dart:3`).

Tri izlaza, redom po preporuci:

1. **Rasterizacija na poslužitelju** (preporuka). SVG sponzora se pri uploadu
   pretvori u PNG u 2–3 veličine i posluži s CDN-a, a SVG ostaje izvor istine
   za buduće regeneriranje. Time se svojstvo koje ti je bitno — „vektor se
   pravilno regenerira za bilo koji omjer" — **zadržava**, samo se regeneracija
   seli s uređaja na poslužitelj. Bonus: dijeli cjevovod s keširanjem OG slika
   (§2.5), pa je to jedan posao umjesto dva.
2. **Retestirati zabranu.** Datira iz ranijeg Fluttera i možda je zastarjela,
   kao što je zabrana `ensureSemantics` opovrgnuta 22.7.2026. Zaslužuje spike
   od pola sata prije nego se prihvati kao činjenica — ali **ne smije se
   pretpostaviti da je pala**.
3. `vector_graphics` (prekompilirani `.vec`) — tehnički najčišće, ali traži
   kompilaciju po uploadu i egzotičan je; samo ako 1 i 2 padnu.

### 2.3 Nova informacijska arhitektura

```
┌─ HERO ────────────────────────────────────────────────────────┐
│ [avatar]  Podrži DOMOVINA podcast                             │
│ Jedna rečenica: kamo novac ide i zašto.                       │
│                                                               │
│   ┌───────────────────────────────────────┐                   │
│   │                                       │  57,01 €          │
│   │        MREŽA 120×120                  │  11 podržavatelja │
│   │        (primarni element)             │  46 od 14.400     │
│   │                                       │                   │
│   │   [ lupa ]              [ ⛶ ]         │  [ Uzmi kvadratić]│
│   └───────────────────────────────────────┘                   │
│   14.400 kvadratića. 46 zauzeto. Bliže središtu = veći iznos. │
└───────────────────────────────────────────────────────────────┘
  Zid podrške · Kako to radi · Na lancu              ← sidra

① PODRŽI  (otvara se tapom na kvadratić ILI na CTA)
   ┌ odabrano: ◧ 60:60 · 5 € ──────────── [ promijeni mjesto ] ┐
   │ Ime ili nadimak      → Ovako ćeš biti potpisan na zidu     │
   │ Poveznica (neobavezno) → Tvoja stranica, projekt ili firma │
   │ Poruka (neobavezno)                                        │
   ├ Ovako će izgledati tvoja pločica i kartica ───────────────┤
   │ [▪]   [slika] hobba.io                    1 €              │
   │       Hobba — on-chain nadzor pozicije                     │
   └ [ Podrži s 5 € ]        ☐ Doniraj anonimno ────────────────┘
   sitno ispod: „Ne želiš birati mjesto? Doniraj bilo koji iznos →"

② ZID PODRŠKE          [ Svi ] [ S poveznicom ] [ Najnoviji ]
   staggered mreža, dvije dopuštene visine, bez rupa
   = legenda mreže, ne zaseban feed

③ KAKO TO RADI      Safe 2-od-3 · platforma nema pristup sredstvima
④ NA LANCU          trenutno stanje, provjeri bilo tko, neovisno o nama
⑤ PODNOŽJE          primatelj, kontakt, uvjeti
```

**Tieri s fiksnim iznosima (1/5/10 €) padaju na dno kao rezervni put** — jedan
redak teksta za onoga tko ne želi birati mjesto. Odabir kvadratića **jest**
odabir iznosa; dva usporedna načina da se kaže isto bila bi upravo ona vrsta
dvostrukosti koja ekran čini nabacanim.

Desktop ostaje dvostupčan (mreža + akcija gore, zid ispod) **ali stranica scrolla
kao jedan dokument** — trostupčani fiksni viewport iz `:495` je glavni krivac za
dojam „nabacano". Ljepljiva traka na dnu (obrazac `PinkaSupportBar` već postoji)
drži CTA dohvatljivim.

**Zamka (CLAUDE.md)**: ako se u `bottomNavigationBar` slaže više traka koje se
nezavisno pale/gase, donji `SafeArea` ide na **zajednički Column**, nikad na
pojedinu traku.

**Zamka (perf)**: mreža danas radi „fenomenalno brzo" jer je jedan paint pass
(`pinka_grid_wall`, vidi `docs` uz slots). Pločice sa slikama **ne smiju** to
srušiti — slike se crtaju samo na razini lupe/punog zaslona, gdje ih je najviše
nekoliko stotina, nikad na pregledu cijele mreže. Mjeriti prije i poslije.

### 2.4 Tri polja i živi pregled kartice

Ovo jednim potezom rješava 1.1 i 1.2:

| Polje | `labelText` | `helperText` |
|---|---|---|
| Ime | „Ime ili nadimak" | „Ovako ćeš biti potpisan na zidu" |
| Poveznica | „Poveznica (neobavezno)" | „Tvoja stranica, projekt ili firma" |
| Poruka | „Poruka (neobavezno)" | — |

- **`labelText`, ne `hintText`** — Material label pluta iznad polja i **ostaje
  vidljiv nakon upisa**. To je cijeli popravak točke 2.
- **Živi pregled kartice ispod obrasca** je jači od bilo kojeg objašnjenja:
  korisnik vidi točan ishod prije plaćanja. Prazna polja → prigušeni placeholder.
- **Migracija podataka**: novi stupac `contributions.link_url`.
  `pinka-webhook` mijenja izvor URL-a u `coalesce(link_url, prvi URL iz message,
  prvi URL iz display_name)` — treći član je *backfill* za postojeće zapise
  poput Igorovog, ne trajno ponašanje.
- Validacija poveznice u klijentu (shema, dužina) prije slanja, plus postojeći
  `safeUrl` na workeru.

### 2.5 Slike u preview karticama, bez odavanja IP-a

Nikad `Image.network` na tuđi host. Umjesto toga **keširamo kod sebe u trenutku
dohvata OG-a** (`pinka-webhook`, dakle jednom po doprinosu, ne po posjetitelju):

```
pinka-webhook (nakon plaćanja)
  → POST /api/og-preview           (postojeće)
  → NOVO: POST /api/og-image-cache { url: preview.image }
      worker: fetch slike (cap 2 MB, samo image/*, timeout 4 s)
              → resize/recompress na ≤ 600 px, JPEG q80
              → R2 / CDN: og-cache/<sha256(url)>.jpg
      vraća: cdn.domovina.ai/og-cache/<hash>.jpg
  → link_preview.image_cached = <cdn url>
```

Zid renderira **isključivo `image_cached`**, nikad `image`. Ako keširanje padne,
kartica ostaje tekstualna kao danas — degradacija bez praznog okvira.

Uz to:
- `CachedThumbnail` (disk-persistent) umjesto golog `Image.network`, kao svugdje.
- Kill-switch: `message_hidden` već skriva poruku i preview; treba i
  `image_hidden` za slučaj neprikladne slike uz inače uredan tekst.
- **Otvoreno pitanje**: keširanje tuđe slike na naš CDN je reprodukcija tuđeg
  sadržaja. Za OG slike je to uvriježena praksa (svi messengeri to rade) i
  autor ju je sam objavio za tu svrhu, ali vrijedi jedna rečenica u `/terms`.

### 2.6 Zid bez rupa

`Wrap` → **staggered mreža s točno dvije dopuštene visine kartice**:

- **Visoka** (2 jedinice) — ima poveznicu: slika, ime, iznos, naslov (2 retka).
- **Niska** (1 jedinica) — nema poveznice: ime, iznos, poruka (1 redak).

Dvije visine daju ritam sponzorskog zida i **matematički uklanjaju rupe** (za
razliku od masonryja s proizvoljnim visinama, koji ih samo smanjuje). Puni tekst
poruke i opis preview kartice sele u **detaljni sheet na tap** — time nestaje i
duplirani URL iz 1.3, jer se u kartici prikazuje ili linkificirani tekst ili
preview, nikad oboje.

Implementacija: `flutter_staggered_grid_view` (`StaggeredGrid` s
`mainAxisCellCount: 1 | 2`). Dodaje ovisnost u `pubspec.yaml` — svjesno, jer je
ručno balansiranje stupaca bez poznatih visina nepouzdano na webu.
**PROVJERITI: radi li paket na `--wasm` buildu** prije nego uđe u task.

### 2.7 Spoj mape i zida

Nakon što viewovi dobiju zajednički ključ (1.5):

- **Hover/fokus na kartici** → pripadajući kvadratić pulsira na mapi.
- **Tap na crveni kvadratić** → zid se doscrolla na tu karticu i ona bljesne
  (isti `flashIds` mehanizam koji već postoji, `pinka_wall_list.dart:62`).
- Kartica doprinosa s mjestom dobiva sitnu koordinatnu oznaku („◧ 60:60").
- Doprinosi **bez** mjesta ostaju bez oznake — ne izmišljamo vezu koje nema.

**Zamka (CLAUDE.md)**: auto-scroll do kartice je `Scrollable.ensureVisible`
unutar ugniježđenog scrolla → povukao bi i stranicu. Treba vlastiti
`ScrollController` i ručni izračun offseta, isti obrazac kao `PeopleRail`.

---

## 3. Otvorena pitanja za tebe

**Riješeno 8.8.2026.**: mreža 120×120 **ostaje primarni identitet ekrana**.
Plan je prepravljen — §2.2 i §2.3 nose novu verziju, §2.1 objašnjava zašto tu
namjerno odstupamo od Sportifyjeva obrasca.

1. **Rezervni iznosi** — 1 / 5 / 10 € u „ne želiš birati mjesto" retku je
   pretpostavka iz trenutnih podataka (46 uplata, prosjek ~1,24 €). Ako je cilj
   podići prosjek, iznosi idu više. Napomena: cijena kvadratića ionako dolazi
   iz zone, pa ovaj redak ne smije nuditi iznos koji je jeftiniji od najjeftinije
   zone — inače mapa postane skuplji put do istog.
2. **Koji način širenja je javni default?** Izvornik ima tri
   (`_expansionMode`, §2.2c). `minimalno` je istina o stanju, `maksimalno`
   izgleda reprezentativno od prvog dana ali sugerira popunjenost koje nema.
   Preporuka: `proporcionalno` na ekranu, `maksimalno` samo za OG sliku i
   press. Treba i odluka smije li se način mijenjati po kampanji.
3. **Tko i kako predaje SVG?** Danas nemamo polje za logo (§2.4 uvodi samo
   „Poveznica"). Varijante: (a) automatski iz `og:image` domene, (b) upload
   SVG-a iznad nekog iznosa, (c) ručna kuracija za velike sponzore. Ovo je
   ujedno i moderacijsko pitanje — logo je veći i vidljiviji od poruke.
4. **Izdvojene poruke kao društveni dokaz** (Sportifyjevi citati) — želiš li
   uređivački biran „istaknuti podržavatelj" na vrhu zida?
5. **Rok kampanje** — postoji li ijedna kampanja s pravim rokom? Bez toga
   nema odbrojavanja.

## 4. Grubi opseg (za kasniju predaju)

| # | Cjelina | Repo | Rizik |
|---|---|---|---|
| A | Tri polja + `labelText` + živi pregled pločice i kartice | domovina.ai | nizak |
| B | `link_url` stupac + webhook fallback lanac | domovina-api | srednji |
| C | Staggered zid + detaljni sheet + uklanjanje duplog URL-a | domovina.ai | nizak |
| D | Keširanje OG slike (worker + R2 + `image_cached`) | pay.domovina.ai + domovina-api | srednji |
| E | Spoj mape i zida (dva stupca u viewovima + highlight u oba smjera) | domovina-api + domovina.ai | nizak |
| F0 | **Spasi `pixel-grid-v1`** — push na GitHub / uvuci u `domovina-storage` | spremni → storage | nizak |
| F1 | Spike: `flutter_svg` na webu danas + rasterizacija SVG→PNG na uploadu | domovina.ai + pay.domovina.ai | srednji |
| F2 | Vraćanje `_expandSponsors` + `_canExpand*` iz izvornika na naš `slots` model | domovina.ai | **visok** |
| F3 | Omjer kao parametar (1:1 / 16:9 / 9:16) + natpis + puni zaslon | domovina.ai | srednji |
| G | Ostatak IA (sidra, ljepljiva traka, blok povjerenja) | domovina.ai | srednji |

Redoslijed nije proizvoljan:

```
F0 → F1 → F2 → F3        (F0 je preduvjet svemu — izvornik nema remote)
D  → F1                  (rasterizacija dijeli cjevovod s keširanjem OG slika)
E  → F2                  (širenje treba vezu doprinos↔mjesto)
A ‖ C                    (neovisni, brza pobjeda, mogu prvi)
```

**F2 je jedini task visokog rizika** — dira `pinka_grid_wall.dart` (1352 linije,
jedan paint pass, jedini razlog zašto mreža radi „fenomenalno brzo"), a ubacuje
algoritam koji u izvorniku ima `maxIterations = 300` petlju (`main.dart:593`).
Definicija gotovog mora sadržavati **izmjereni frame time prije i poslije** i
dokaz da se širenje računa **jednom po promjeni podataka**, nikad u `paint()`.

**Sudar s tekućim krugom**: A, F3 i G diraju `lib/l10n/app_hr.arb` / `app_en.arb`,
a G vjerojatno i `web/_worker.js` — isti fajlovi koje drži glasanje (T3/T5).
Zato ovaj posao **ne smije** krenuti dok glasanje nije integrirano i commitano.
