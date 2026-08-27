# Model troška po vertikali — koliko stvarno košta obraditi jedan sat zvuka

*Izveden 27.8.2026. (analitičar, pitch vertikala, krug 2 / T5). Otvorena stavka
#1 iz [`vc-pitch-strategija.md`](vc-pitch-strategija.md) §9; skeptik ju je
označio kao „ubija posao".*

> **Pravilo po kojem je ovaj dokument pisan.** Model se izvodi **odozdo prema
> gore**: objavljena cijena × naša izmjerena količina. Nijedna stavka nema
> vrijednost bez jednog od toga. Gdje ni jedno ni drugo ne postoji, stavka je
> **raspon s imenovanom pretpostavkom**, nikad točka — i u tablicama je
> označena s **PRETPOSTAVKA**.
>
> Ovo **nije financijski model.** Prihodna strana ostaje prazna i to nije
> propust nego nalaz — vidi §6.

Unosi su strojno provjerljivi u
[`deck/podaci.json`](deck/podaci.json); `provjeri_brojke.py` provjerava da
svaka brojka odavde ima izvor, datum i izvod.

---

## 0. Zaključak u tri retka

1. **Obrada sata zvuka košta €0,12–0,32.** Nosi ga **LLM sloj**, ne
   transkripcija; ASR je 4–11 % ukupnog troška, ovisno o scenariju.
2. **Nova vertikala košta €3.990–16.854, i taj iznos je gotovo neovisan o tome
   ima li 181 ili 3.048 sati** — jer je 91–99 % troška inženjerski rad, a ne
   compute. Novac nije usko grlo; **raspoloživost ta dva inženjera jest**, i
   model je ne cijeni (§4.1).
3. **Stavka „Compute za korpus ~150 tis. EUR" iz §2 je oko 75× veća od onoga
   što model traži za tri vertikale.** To je nalaz o §2, ne o modelu (§5).

---

## 1. Mjerne točke i objavljene cijene

Sve provjereno ili izmjereno **27.8.2026.**

| što | vrijednost | izvor |
|---|---|---|
| Modal A100-40GB | **$0,000583 / s** ($2,099/h) | [modal.com/pricing](https://modal.com/pricing) |
| Modal Starter besplatno | $30 / mj | isto |
| Gemini 2.5 Flash | **$0,30 / $2,50** po 1M tokena (ulaz/izlaz) | [ai.google.dev](https://ai.google.dev/gemini-api/docs/pricing) |
| Gemini 3.5 Flash | **$1,50 / $9,00** po 1M tokena | isto |
| Cloudflare R2 | **$0,015 / GB-mj**, Class A $4,50/M, Class B $0,36/M, **egress besplatan** | [developers.cloudflare.com](https://developers.cloudflare.com/r2/pricing/) |
| R2 besplatno | 10 GB-mj, 1M Class A, 10M Class B | isto |
| EUR/USD | **1,1669** (26.8.2026.) | [ECB referentni tečaj](https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml) |

Naše mjerne točke, sve s naredbom kojom se ponavljaju:

| mjerenje | rezultat | naredba |
|---|---|---|
| ASR batch, 115 ep / 82,1 h | Σ inference 28,7 min, wall 38,2 min | `modal run modal_canary/canary_modal.py::batch --stats-out ...` (29.7.2026.) |
| ASR ad-hoc, 1 datoteka 21,7 min | model load 40 s, **inference 6 s**, wall 78,9 s | `modal run modal_canary/canary_modal.py::main --wav <wav>` (27.8.2026.) |
| Diarizacija, 21,7 min zvuka | **67,5 s** wall na M4 Pro (MPS) | `diarize.py --wav <wav> --srt <srt> --output <out>` (27.8.2026.) |
| Diarizacija, 6 produkcijskih snimki | 1.182 s zvuka → 136 s | `~/Library/Logs/companion-server.log` |
| LLM sloj, **546 epizoda** | medijan $0,0885/ep | `*.gemini_usage.json` u `dataset.domovina.tv/.sync_staging/` |
| Prostor po epizodi | 250 MB (1:44 epizoda) | HEAD na `cdn.domovina.ai/data/<id>/*` |
| Korpus | 48 kanala, 3.189 epizoda, **3.048 h** | `cdn.domovina.ai/channels/data/index.json` |

---

## 2. A — trošak po satu obrađenog zvuka

### 2.1 ASR (Canary 1b-v2 na Modalu)

**RTF je izmjeren, ne pretpostavljen.** Dvije neovisne mjere:

| mjerenje | zvuka | inference | RTF | × realtime |
|---|---:|---:|---:|---:|
| batch, 115 epizoda (29.7.2026.) | 82,1 h | 28,7 min | 0,00583 | 172× |
| jedna datoteka (27.8.2026.) | 0,362 h | 6 s | **0,0046** | **217×** |

Dvije mjere iz različitih mjeseci i različitih režima slažu se unutar 25 % —
to je ono što RTF čini upotrebljivim brojem, a ne jedno mjerenje.

**Ali plaća se uptime containera, ne inference.** Zato režim odlučuje:

| režim | naplaćeno | $/h zvuka | €/h zvuka |
|---|---|---:|---:|
| **batch** (donja granica, samo inference) | 1.722 s | 0,0122 | 0,0105 |
| **batch** (gornja, cijeli wall clock) | 2.292 s | **0,0163** | **0,0140** |
| ad-hoc, jedna datoteka | 166 s (40 load + 6 inf + 120 scaledown) | 0,267 | 0,229 |

Ad-hoc je **17× skuplji po satu zvuka** jer svaki poziv ponovno plaća cold
start i keep-warm. Nova vertikala je bulk unos, dakle batch. **Uzimam gornju
granicu batcha: €0,0140/h.**

### 2.2 Dijarizacija (pyannote 3.1)

Izmjereno danas na M4 Pro, MPS, 1.303,9 s zvuka → **67,5 s** wall
(segmentacija +4 s, embeddings +4→+55 s, klasteriranje +55→+67 s):
**RTF 0,0518 (19,3× realtime)**, 3 govornika.

> **Nalaz o vlastitom dokumentu.** `docs/diarization_research_2026-05.md` tvrdi
> da je M4 Pro „~real-time wall-clock" i na tome gradi odluku „diariziraj na
> Macu". Odluka stoji — ali **broj je pogrešan za ~20×** u našu korist.
> Izmjereno je 19× brže od realtimea, ne 1×.

Šest produkcijskih snimki (2–5 min) daje RTF 0,115 — lošije, jer fiksno
učitavanje modela dominira kratkim datotekama. Na dužoj datoteci se amortizira.

| način | €/h zvuka | napomena |
|---|---:|---|
| **na vlastitom Mac Miniju (današnja produkcija)** | **< 0,001** | 0,052 h stroja × ~40 W = 2,1 Wh/h zvuka; pri bilo kojoj tarifi ispod desetinke centa |
| na najmljenom A100-40 | 0,094 | **PRETPOSTAVKA**: isti RTF na najmljenom GPU-u. Nije izmjereno — pyannote je CPU-vezan u klasteriranju, pa A100 ne mora biti brži od M4 Pro. |

Uzimam **€0,000** za osnovni scenarij (hardver je već plaćen) i **€0,094** kao
gornju granicu za scenarij „bez Maca".

### 2.3 LLM sloj (sažetak + članak, Gemini)

Ovo je **najbolje izmjerena stavka u cijelom modelu**: pipeline zapisuje
`*.gemini_usage.json` po epizodi s brojem tokena i cijenom po modelu.
**546 epizoda** s valjanim zapisom:

| | p25 | medijan | p75 | p90 | prosjek |
|---|---:|---:|---:|---:|---:|
| USD po epizodi | 0,0592 | **0,0885** | 0,1324 | 0,2052 | 0,1179 |
| ulaznih tokena (tis.) | 46,9 | 91,3 | 153,3 | 202,0 | 110,9 |
| izlaznih tokena (tis.) | 12,4 | 16,9 | 21,4 | 25,7 | 18,2 |

Po modelu: **2.5 Flash medijan $0,0722/ep** (n=428), **3.5 Flash medijan
$0,1854/ep** (n=114) — 2,6× skuplje, što odgovara omjeru objavljenih cijena.
Provjerio sam da zapisi nose ispravnu cijenu po modelu (1,50/9,00 za 3.5), pa
`est_usd` nije podcijenjen.

Prosječna epizoda u korpusu traje **57,4 min** (3.048 h / 3.189 ep), pa:

| | $/h zvuka | €/h zvuka |
|---|---:|---:|
| medijan | 0,0925 | **0,0793** |
| p90 | 0,2145 | **0,1838** |

### 2.4 Prostor i CDN (R2)

Izmjereno na epizodi `WRE248YCIeI` (1:44:07):

| objekt | veličina |
|---|---:|
| `video_h264.mp4` | 179,2 MB |
| 44 screenshota × ~1,66 MB | 69,7 MB |
| `thumbnail.png` + `og-share.jpg` | 0,82 MB |
| `diarized.srt` + `article.json` + `info.json` + `outline.json` + `summary.json` | 0,34 MB |
| **ukupno** | **250,1 MB** |

Video preko pet nasumičnih kanala: **83–97 MB/h** (medijan ~92), uska raspodjela.
Screenshotovi mjereni na **n=1** → ~40 MB/h, **PRETPOSTAVKA** da je gustoća
sličica slična drugdje.

Ukupno **~133 MB/h zvuka** → 0,1299 GB × $0,015 = **$0,00195 po satu zvuka
mjesečno**, odnosno **$0,0351 / €0,0301 kroz 18 mjeseci**.

Class A/B operacije: nekoliko desetaka po epizodi; pri $4,50/M to je ispod
$0,0002 po epizodi i cijelo vrijeme unutar besplatnog sloja. **Egress je
besplatan** — isporuka sadržaja ne košta ništa, i to je jedina stavka koja bi
inače rasla s gledanošću.

### 2.5 Zbroj — €0,12 do €0,32 po satu zvuka

| stavka | osnovni (vlastiti Mac, medijan LLM) | gornji (najmljen GPU, p90 LLM) |
|---|---:|---:|
| ASR | 0,0140 | 0,0140 |
| dijarizacija | 0,000 | 0,0940 |
| LLM sloj | 0,0793 | 0,1838 |
| prostor (18 mj) | 0,0301 | 0,0301 |
| **€ / h zvuka** | **0,123** | **0,322** |

**Gdje ide novac (osnovni scenarij): 64 % u LLM sloj, 24 % u prostor, 11 % u ASR.** Transkripcija,
koja je u razgovoru uvijek prva stavka koju netko spomene, je najjeftiniji dio.

### 2.6 Što u ovom zbroju NIJE

Da se ne prodaje kao potpunije nego što jest — ove stavke nisu izmjerene i nisu
u zbroju:

- **EN prijevod** (`summary.en.json`, `article.en.json`) — isti Gemini put, pa
  bi otprilike **udvostručio LLM sloj** kad se uključi. Danas je uključen na
  malom dijelu korpusa.
- Magisterium obogaćivanje, RAG embeddingi, video transcode (lokalno, na već
  plaćenom hardveru), yt-dlp egress, ljudska kontrola kvalitete.
- **Ponovna obrada pri promjeni modela.** Jednom plaćeno nije zauvijek: prelazak
  na bolji ASR znači ponovno platiti cijeli korpus.

Čak i da sve to utrostruči zbroj, zaključak §5 se ne mijenja.

---

## 3. B — koliko sati ima jedna vertikala

Iz `cdn.domovina.ai/channels/data/index.json`, 27.8.2026. — 48 kanala:

| | min | p25 | medijan | p75 | p90 | max | prosjek |
|---|---:|---:|---:|---:|---:|---:|---:|
| sati po kanalu | 2,2 | 9,5 | **36,1** | 76,4 | 158,7 | 345,1 | 63,5 |
| epizoda po kanalu | 1 | 12 | 43 | 81 | 179 | 316 | 66,4 |

Raspodjela je jako iskrivljena (prosjek 63,5 h naspram medijana 36,1 h), pa
prosjek sam po sebi zavarava. Gornja tablica je **izmjerena**; donja nije, i to
je razlika koju treba vidjeti prije nego se brojke pročitaju.

> **Broj kanala po scenariju nije mjerenje.** Sati po kanalu jesu — dolaze iz
> `index.json`. Koliko kanala ima „jedna vertikala" nitko nije izmjerio, jer
> postoji točno jedna postojeća vertikala. Zato scenariji dolje **nisu izbor po
> osjećaju nego dvije rubne točke koje se daju obraniti**, plus interpolacija
> između njih koja je označena kao takva.

- **Donja rubna točka: 5 kanala.** Nije odabrana nego **preuzeta iz vlastite
  prekretnice** — `vc-pitch-strategija.md` §2 obećava „20 plaćenih trenutaka
  kroz **najmanje 5 kanala**". Vertikala s manje od pet kanala ne može ispuniti
  obećanje koje deck već daje, pa je to najmanja vertikala koja ima smisla.
- **Gornja rubna točka: 48 kanala.** Nije odabrana nego **opažena** — toliko ih
  danas ima naša vlastita vertikala.
- Sve između su interpolacije. Navedene su da se vidi kako se compute mijenja,
  a ne kao tvrdnja o tome kolika će nova vertikala biti.

| scenarij | kanala | sati | compute €0,123/h | compute €0,322/h |
|---|---|---:|---:|---:|
| **najmanja koja ispunjava prekretnicu** | 5 × medijan 36,1 (rubna točka, iz §2) | **181** | 22 | 58 |
| interpolacija | 10 × medijan 36,1 (PRETPOSTAVKA) | 361 | 44 | 116 |
| interpolacija | 25 × prosjek 63,5 (PRETPOSTAVKA) | 1.588 | 195 | 511 |
| **zrcalo današnje** | 48 × prosjek 63,5 (opaženo) | **3.048** | 375 | 981 |

**Compute za cijelu novu vertikalu veličine naše je ispod tisuću eura**, a
raspon od najmanje do najveće vertikale mijenja ga za manje od 960 EUR — što je
manje od troška četiri inženjer-dana.

---

## 4. C — ono što nije compute

### 4.1 Trošak inženjerskog dana, izveden iz §2 a ne s tržišta

`vc-pitch-strategija.md` §2: **2 inženjera, ~200 tis. EUR, 18 mjeseci.**

```
200.000 EUR / 2 inženjera / 18 mjeseci = 5.555,56 EUR po inženjer-mjesecu
5.555,56 / 21 radni dan                = 264,55 EUR po inženjer-danu
```

Namjerno se **ne** koristi tržišna satnica: pitanje je što vertikala košta
**nas, iz ovog budžeta**, a ne koliko bi netko naplatio.

> **Ograničenje koje ova brojka nosi, i koje se ne smije prešutjeti.**
> 264,55 EUR je **prosječna cijena jednog dana iz budžeta**, a **ne
> oportunitetni trošak tog dana**. Formula dijeli plaću na dane i tretira svaki
> dan kao slobodan za novu vertikalu. Nije slobodan: **isti par inženjera
> istovremeno duguje četiri prekretnice** — 20 plaćenih trenutaka, 5 izvršenih
> otkupa, 3 vertikale na white-labelu i jednu stranu vertikalu — plus dovršetak
> on-chain isplate kreatorima koju slajd 14 vodi kao nedovršenu. Dan potrošen na
> treću vertikalu je dan koji **nije otišao na jednu od tih prekretnica**, i
> model taj gubitak **ne računa**.
>
> Ovo je isto usko grlo koje slajd 15 već priznaje za jednog osnivača. Za dvoje
> ljudi ono ne nestaje nego postaje manje vidljivo, jer se sakrije iza čistog
> broja po danu.

Jedino što se o kapacitetu može reći bez izmišljanja jest koliko ga ukupno ima,
jer i to izlazi iz istog §2:

```
2 inženjera × 18 mjeseci × 21 radni dan = 756 inženjer-dana ukupno
3 vertikale × 15–60 dana                =  45–180 inženjer-dana  (6–24 % kapaciteta)
```

Dakle prekretnica „3 vertikale" troši **6 do 24 % cjelokupnog inženjerskog
kapaciteta** koji ovaj ask kupuje. Preostalih 76–94 % mora pokriti sve ostalo
što je obećano.

**Što model NE može reći:** stane li to. Nijedna od preostale tri prekretnice
nije procijenjena u inženjer-danima, pa se ne zna je li 76 % dovoljno ili je
premalo. **Zatvara to jedino plan kapaciteta** — ista razrada od pet poslova iz
§4.2, napravljena i za 20 trenutaka, 5 otkupa i on-chain isplatu, pa zbroj
usporediti sa 756. Dok toga nema, na pitanje „ako dan ode na treću vertikalu,
koja prekretnica kasni" **pošten odgovor je da ne znamo**, a ne brojka izvedena
unatrag da odgovor postoji.

### 4.2 Inženjer-dani po vertikali — PRETPOSTAVKA, i to najslabija u dokumentu

Ovo je jedina veličina u modelu koja **nije izmjerena**. Nemamo instrumentiranu
nijednu prošlu vertikalu, pa se broj ne može izvesti — može se samo razložiti na
poslove koji su dokumentirani drugdje:

| posao | zašto je stvaran, a ne pretpostavljen | dana |
|---|---|---:|
| otkrivanje i onboarding kanala | `crm/podcasts/scripts/build_catalog.py`, per-kanal enrichment | 3–10 |
| jezični par i validacija ASR-a | `modal_canary/README.md`: **nema auto-detecta**, EN kanali moraju ići `--source-lang en` ručno | 2–8 |
| prilagodba promptova i taksonomije | `PIPELINE.md` §7–8, dvofazni članak s per-vertikalnim rječnikom | 5–20 |
| ugađanje dijarizacije | A/B dokument: pyannote na šumnom audiju **eksplodira do 29 govornika** | 2–10 |
| kontrola kvalitete prvih N epizoda | **PRETPOSTAVKA UNUTAR PRETPOSTAVKE** — da posao postoji, dokazuju tri dokumentirana tiha kvara (dolje); koliko traje, nitko nije mjerio | 3–12 |
| **ukupno** | | **15–60** |

Četiri gornja retka pokazuju na dokument koji im daje oblik. **Peti ne, i to je
najslabija brojka u cijelom modelu** — slabija i od samog raspona 15–60, jer
unutar njega nosi do trećine gornje granice bez ijedne reference.

Ono što se o tom retku **može** obraniti jest da posao postoji, jer su kvarovi
koje hvata dokumentirani i svi su **tihi** — prođu pipeline bez greške i vide se
tek na živoj epizodi:

- `PIPELINE.md` §8: generiranje članka „povremeno truncates kompleksne iteracije
  na zadnjoj sekciji (JSON parse error → resume na ponovnom run-u)".
- `pipeline_publish_egress_r2_2026-06.md` §4: pogrešno razriješen `_yt_` prefiks
  dao je R2 ključeve pod krivim imenom → **404 na sve slike dvije žive epizode**.
- `diarization_sortformer_vs_pyannote_ab_2026-06.md`: pyannote na šumnom audiju
  **eksplodira do 29 govornika**.

Ono što se **ne** može obraniti je broj dana. Tri do dvanaest nije izvedeno ni
iz čega — to je procjena, i ovdje je označena kao takva umjesto da se sakrije u
tablicu s četiri potkrijepljena retka.

```
15 dana × 264,55 EUR =  3.968 EUR
60 dana × 264,55 EUR = 15.873 EUR
```

**Što bi ovu pretpostavku pretvorilo u mjerenje:** instrumentirati sljedeću
vertikalu — bilježiti dane po gornjih pet poslova od prvog commita do prve žive
epizode. Jedna vertikala daje jednu točku, tri daju raspon. Do tada je ovo
raspon, i skeptik ga ima pravo napasti prvog.

### 4.3 Ukupno po vertikali

| scenarij | compute | inženjering | **ukupno** | udio computea |
|---|---:|---:|---:|---:|
| najmanja (181 h), donja | 22 | 3.968 | **3.990 €** | 0,6 % |
| zrcalo (3.048 h), donja | 375 | 3.968 | **4.343 €** | 8,6 % |
| najmanja (181 h), gornja | 58 | 15.873 | **15.931 €** | 0,4 % |
| zrcalo (3.048 h), gornja | 981 | 15.873 | **16.854 €** | 5,8 % |

> **Ovo je nalaz koji vrijedi izgovoriti na sastanku.** Vertikala od 3.048 sati
> košta **9 % više** od vertikale od 181 sata — sedamnaest puta više sadržaja za
> devet posto veći trošak. Trošak je gotovo potpuno neovisan o količini sadržaja
> jer je gotovo potpuno inženjerski. To je brojka ispod tvrdnje sa slajda 11 da
> je „nova vertikala konfiguracija" — i ujedno razlog zašto je prva stavka
> namjene sredstava dva inženjera, a ne compute.
>
> **Ali brojka govori o novcu, ne o vremenu.** Cijena vertikale je niska;
> raspoloživost ljudi koji je rade nije riješena — vidi ogradu u §4.1.

Prekretnica **3 vertikale uživo na white-labelu**: **11.970–50.562 EUR**, ili
1–4 % traženih 1,2 M EUR — ali **6–24 % raspoloživog inženjerskog kapaciteta**
(§4.1). Jeftino u eurima, skupo u danima, i to je omjer koji treba nositi u sobu.

---

## 5. D — provjera zdravlja naspram §2, i nalaz o §2

`vc-pitch-strategija.md` §2 predviđa **~150 tis. EUR za „Compute za korpus"**
kroz 18 mjeseci. Model kaže:

```
150.000 EUR / 0,123 EUR po satu = 1.219.512 sati zvuka
150.000 EUR / 0,322 EUR po satu =   465.839 sati zvuka
```

To je **153× do 400× cijeli današnji korpus** (3.048 h). Tri vertikale veličine
zrcala (9.144 h) koštaju **1.125–2.944 EUR**.

> **NALAZ O §2, NE O MODELU.** Stavka od 150 tis. EUR je oko **75× veća** od
> onoga što obećane prekretnice traže. Model nisam prilagođavao da se poklopi,
> kako plan kruga 2 izričito traži.

Poštena strana argumenta — što bi tu stavku moglo opravdati, a §2 ne kaže:
ponovna obrada cijelog korpusa pri promjeni modela, EN prijevod cijelog korpusa,
vlastito fino ugađanje ASR-a, ili prelazak s Gemini Flasha na skuplji model.
Ali **ništa od toga nije napisano**, a razlika je dva reda veličine — dovoljno
velika da je preživi i trostruko podcijenjen model.

Preporuka, ne odluka: ili stavku spustiti i razliku prebaciti na inženjere (gdje
model pokazuje da je usko grlo), ili u §2 napisati što točno tih 150 tis. kupuje.
Investitor koji ovo izračuna prije nas — a IAB-ove i Modalove cijene su javne —
dobiva besplatan argument da brojke u decku nisu izvedene.

---

## 6. E — što ovaj dokument NE zatvara

**Ovo nije financijski model.** Model troška daje samo jednu stranu.

**Prihodna strana ostaje nepoznata i ne pokušava se zaobići.** CPM za hrvatski
podcast **javno ne postoji** — to je redak §7 popisa nepotvrđenog u
[`../oglasni-prostor-trziste-i-usporedba.md`](../oglasni-prostor-trziste-i-usporedba.md),
i zabrana vrijedi i ovdje. Nijedna brojka iz ovog dokumenta se ne smije
pomnožiti s pretpostavljenom cijenom da bi nastala projekcija prihoda: §7
zabranjuje i „projekcije prihoda s decimalama".

Prva cijena nastaje kad se proda prvi trenutak. Do tada je jedino što se pošteno
zna **trošak**, i on je sad izveden.

---

## 7. Prilog — projekcija floata (`float-45m-bez-modela`)

Slajd 9 računa prinos na prosječnom floatu od **~45 M EUR**. Množenje je točno
(45 M × 2,25 % = 1,01 M EUR godišnje) i stopa je provjerena, ali **ulazni iznos
nema izvod**. Ovdje je.

Float nije slobodan parametar — određuju ga tri veličine:

```
prosječan float = broj trenutaka u letu × cijena trenutka × (dani zadržavanja / 548)
```

548 dana = 18 mjeseci obećanog razdoblja. Cijena trenutka je **nepoznata**
(§7), pa se uzima raspon, i to je označeno kao PRETPOSTAVKA.

Pri obećanim prekretnicama — **20 plaćenih trenutaka kroz 18 mjeseci**:

| pretpostavka | trenutaka | cijena | zadržavanje | prosječan float | prinos @ 2,25 % |
|---|---:|---:|---:|---:|---:|
| donja | 20 | 200 € | 30 dana | **219 €** | 4,93 €/god |
| gornja | 20 | 2.000 € | 90 dana | **6.569 €** | 147,8 €/god |

**Razlika prema 45 M EUR je četiri reda veličine.** Da bi float dosegao 45 M uz
cijenu od 1.000 € i zadržavanje od 30 dana, trebalo bi **822.000 trenutaka u 18
mjeseci** — 41.000× više od obećanih dvadeset.

Iz toga slijedi troje, i sve troje ide autoru i skeptiku, ne u slajd bez odluke:

1. **Ograda na slajdu 9 („~0 today", „path, not revenue") je točna** i drži
   brojku poštenom. Bez nje bi bila crvena.
2. **45 M EUR ne pripada ovom asku.** Ne postiže se nijednom kombinacijom
   obećanih prekretnica. Pripada airKUNA sloju na skali — što je upravo ono što
   rečenica „jedno društvo, dva sloja" iz kruga 2 kaže, pa brojku treba
   **pripisati tom sloju**, ne ovom planu.
3. Ako brojka ostaje, uz nju mora stajati **od čega je izvedena**, jer sada je
   to jedina brojka na slajdu 9 bez izvoda: 1 M EUR ÷ 2,25 % = 44,4 M EUR,
   dakle iznos je izveden **unatrag iz željenog prinosa**, a ne unaprijed iz
   plana. To je odozgo prema dolje, i točno je ono što se u ovoj vertikali
   inače zabranjuje.

---

## 8. Usput — nalaz o trajanju epizode `WRE248YCIeI`

Pri mjerenju sam naletio na ispravak vlastitog nalaza iz kruga 1. Postoje **tri**
vrijednosti za trajanje iste epizode:

| izvor | vrijednost | što zapravo mjeri |
|---|---|---|
| `cdn.domovina.ai/channels/data/domovina_tv.json` | **6247 s = 1:44:07** | trajanje videa (YouTube metapodaci) |
| `mcp.domovina.link` `get_episode` `duration_sec` | 6244 s = 1:44:04 | kraj zadnjeg poglavlja |
| zbroj `flex` vrijednosti trake na slajdu 4 | 6244 s = 1:44:04 | isto — traka je građena iz poglavlja |

U krugu 1 sam autoru javio „1:44:06 → 1:44:04 na oba mjesta". **To je točno za
os trake, ali ne i za natpis o trajanju epizode**, gdje je mjerodavan CDN i
vrijednost je **1:44:07**. Dvije brojke mjere dvije različite stvari i deck ih
ne smije stopiti: os ide do kraja zadnjeg poglavlja, epizoda traje 3 s dulje.
Isti popravak treba i u `docs/2026-08-26-pitch-deck-orakl.md` §4 (piše 1:44:06)
i u `deck/README.md` (piše 1:44:07 za os — obrnuto od ispravnog).
