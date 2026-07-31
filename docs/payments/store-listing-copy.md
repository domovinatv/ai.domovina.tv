# Store listing copy — App Store i Google Play

Kanonski tekst opisa aplikacije za obje trgovine, HR i EN, usklađen sa
**stvarnim** stanjem produkta na dan **2026-07-31**. Nastalo kao T4 plana
`docs/plans/2026-07-31-plus-posteni-paywall.md`, nakon revizije koja je
utvrdila da je paywall nabrajao sedam pogodnosti, a postojale su dvije.

> **Ovaj tekst se NE deploya.** Nema API-ja za listing tekst ni u App Store
> Connectu ni u Play Consoleu — kopira se **ručno**, u obje konzole. Ovaj
> dokument je izvor istine; konzola je samo kopija. Kad se mijenja jedno,
> mijenja se i drugo, u istom danu.

---

## 1. Što Plus danas STVARNO jest

Prije bilo kakvog pisanja o Plusu — ovo je cijeli popis. Izveden je iz koda,
ne iz namjere: u cijelom appu postoje **dva** mjesta koja čitaju
`EntitlementService.isPlus`.

| Pogodnost | Gdje živi u kodu | Provjerljivo |
|---|---|---|
| Šira pretraga — do 30 rezultata umjesto 12 | `lib/screens/home/search_overlay.dart` (`isPlus ? 30 : 12`) | da |
| Bedž podupiratelja | `lib/widgets/plus_badge.dart` | da |
| Podrška radu i troškovima arhive | — (nije značajka, nego iskren razlog) | n/p |

Sve ostalo u aplikaciji **besplatno je i ostaje besplatno**: reprodukcija,
transkripti, sažetci, članci, Magisterium analiza, poglavlja, pretraga (uz
manji broj rezultata), favoriti i nastavak slušanja, hrvatski i engleski.

**Sinkronizacija favorita i napretka je besplatna svim prijavljenima** — nikad
je ne pisati kao Plus pogodnost. To je bila najkonkretnija netočnost u starom
copyju.

Cijene (poklapaju se s `pricing-and-tiers.md` i sa stvarnim store proizvodima
u `provisioning-state.md` §2): **4,99 €/mj**, **39,99 €/god**, **99,99 €
jednokratno (doživotno)**.

---

## 2. App Store (HR)

**Ime aplikacije** (≤30 znakova)

```
DOMOVINA.ai
```

**Podnaslov** (≤30 znakova)

```
Hrvatski podcasti uz AI
```

**Ključne riječi** (≤100 znakova, zarezom odvojeno, bez razmaka)

```
podcast,transkript,sažetak,katolički,vjera,hrvatski,arhiva,epizode,govornici,pretraga
```

**Promotivni tekst** (≤170 znakova; mijenja se bez novog reviewa)

```
Nove epizode svaki tjedan — s transkriptom, sažetkom i analizom čim izađu. Slušaj, čitaj ili pretraži cijelu arhivu.
```

**Opis** (≤4000 znakova)

```
DOMOVINA.ai je arhiva hrvatskih podcasta koju umjetna inteligencija razlaže na dijelove koje možeš čitati, pretraživati i preskakati.

Svaka obrađena epizoda dolazi sa sažetkom, poglavljima s vremenskim oznakama, transkriptom u kojem se zna tko govori i člankom koji epizodu prepričava po odsjecima. Katoličke epizode dodatno prolaze Magisterium AI analizu — usporedbu izrečenog s crkvenim naukom, uz navedene izvore.

ŠTO MOŽEŠ

• Slušati i gledati epizode, s reprodukcijom u pozadini
• Skakati po poglavljima umjesto premotavanja
• Čitati transkript s označenim govornicima i pratiti ga uz zvuk
• Pročitati sažetak i članak umjesto cijele epizode kad nemaš sat vremena
• Vidjeti Magisterium AI analizu usklađenosti s katoličkim naukom
• Pretraživati arhivu — po riječi i po značenju
• Otvoriti profil osobe i vidjeti gdje govori, a gdje se spominje
• Spremiti epizodu u favorite i nastaviti tamo gdje si stao, na svim uređajima
• Podijeliti epizodu s točnom sekundom na kojoj je rečeno ono što šalješ
• Prebaciti sučelje i sadržaj između hrvatskog i engleskog, gdje prijevod postoji

Sve gore navedeno je besplatno. Ne postoji zid oko sadržaja, transkripata ni analiza.

DOMOVINA PLUS

Plus je način da podupreš arhivu. Uz to dobivaš:

• Širu pretragu — do 30 rezultata umjesto 12
• Bedž podupiratelja na tvom računu

Toliko, doslovno. Ne obećavamo ništa što danas ne radi. Smjerove razvoja držimo odvojeno, u sekciji „U planu" unutar aplikacije, i jasno je označeno da nisu dio kupnje.

Pretplata: 4,99 € mjesečno ili 39,99 € godišnje, s automatskom obnovom. Postoji i doživotni pristup za 99,99 € jednokratno, bez obnove.

Pretplata se automatski obnavlja osim ako je ne otkažeš najmanje 24 sata prije isteka razdoblja. Naplata ide preko tvog Apple ID računa, a pretplatom upravljaš u postavkama računa. Doživotni pristup je jednokratna kupnja i ne obnavlja se.

Uvjeti korištenja: https://domovina.ai/terms
Politika privatnosti: https://domovina.ai/privacy
```

---

## 3. Google Play (HR)

**Naziv aplikacije** (≤30 znakova)

```
DOMOVINA.ai
```

**Kratki opis** (≤80 znakova)

```
Transkripti, sažetci i analize hrvatskih podcast epizoda.
```

**Potpuni opis** (≤4000 znakova)

```
DOMOVINA.ai je arhiva hrvatskih podcasta koju umjetna inteligencija razlaže na dijelove koje možeš čitati, pretraživati i preskakati.

Svaka obrađena epizoda dolazi sa sažetkom, poglavljima s vremenskim oznakama, transkriptom u kojem se zna tko govori i člankom koji epizodu prepričava po odsjecima. Katoličke epizode dodatno prolaze Magisterium AI analizu — usporedbu izrečenog s crkvenim naukom, uz navedene izvore.

ŠTO MOŽEŠ

• Slušati i gledati epizode, s reprodukcijom u pozadini
• Skakati po poglavljima umjesto premotavanja
• Čitati transkript s označenim govornicima i pratiti ga uz zvuk
• Pročitati sažetak i članak umjesto cijele epizode kad nemaš sat vremena
• Vidjeti Magisterium AI analizu usklađenosti s katoličkim naukom
• Pretraživati arhivu — po riječi i po značenju
• Otvoriti profil osobe i vidjeti gdje govori, a gdje se spominje
• Spremiti epizodu u favorite i nastaviti tamo gdje si stao, na svim uređajima
• Podijeliti epizodu s točnom sekundom na kojoj je rečeno ono što šalješ
• Prebaciti sučelje i sadržaj između hrvatskog i engleskog, gdje prijevod postoji
• Koristiti aplikaciju i na Android TV-u, s daljinskim

Sve gore navedeno je besplatno. Ne postoji zid oko sadržaja, transkripata ni analiza.

DOMOVINA PLUS

Plus je način da podupreš arhivu. Uz to dobivaš:

• Širu pretragu — do 30 rezultata umjesto 12
• Bedž podupiratelja na tvom računu

Toliko, doslovno. Ne obećavamo ništa što danas ne radi. Smjerove razvoja držimo odvojeno, u sekciji „U planu" unutar aplikacije, i jasno je označeno da nisu dio kupnje.

Pretplata: 4,99 € mjesečno ili 39,99 € godišnje, s automatskom obnovom preko Google Play računa. Otkazuje se u Google Play trgovini, pod Pretplate. Doživotni pristup je jednokratna kupnja od 99,99 € i ne obnavlja se.

Sadržaj epizoda dolazi s javno objavljenih YouTube kanala; transkripti, sažetci i analize generirani su umjetnom inteligencijom i mogu sadržavati pogreške.

Uvjeti korištenja: https://domovina.ai/terms
Politika privatnosti: https://domovina.ai/privacy
```

Napomena: Android TV stavku držimo **samo** u Play opisu (Apple listing nema
TV build), a AI-disclaimer rečenicu držimo u Playu jer Play politika o
generativnoj umjetnoj inteligenciji traži jasno označavanje AI sadržaja.

---

## 4. App Store (EN)

**Subtitle** (≤30)

```
Croatian podcasts with AI
```

**Keywords** (≤100)

```
podcast,transcript,summary,catholic,faith,croatian,archive,episodes,speakers,search
```

**Promotional text** (≤170)

```
New episodes every week — with a transcript, a summary and analysis as soon as they land. Listen, read, or search the whole archive.
```

**Description** (≤4000)

```
DOMOVINA.ai is an archive of Croatian podcasts, broken down by AI into parts you can read, search and skip through.

Every processed episode comes with a summary, chapters with timestamps, a transcript that tells you who is speaking, and an article that retells the episode section by section. Catholic episodes also go through Magisterium AI analysis — a comparison of what was said with Church teaching, with sources cited.

WHAT YOU CAN DO

• Listen and watch, with background playback
• Jump between chapters instead of scrubbing
• Read the transcript with speakers labelled, and follow it as the audio plays
• Read the summary and the article when you don't have an hour to spare
• See the Magisterium AI analysis of alignment with Catholic teaching
• Search the archive — by word and by meaning
• Open a person's profile and see where they speak and where they are mentioned
• Save episodes to favourites and pick up where you left off, on any device
• Share an episode at the exact second where the thing you're sending was said
• Switch interface and content between Croatian and English, where a translation exists

All of the above is free. There is no wall around the content, the transcripts or the analysis.

DOMOVINA PLUS

Plus is a way to support the archive. You also get:

• Broader search — up to 30 results instead of 12
• A supporter badge on your account

That's it, literally. We don't promise anything that doesn't work today. Directions we're exploring are kept separate, in an "On the roadmap" section inside the app, clearly marked as not part of the purchase.

Subscription: €4.99 monthly or €39.99 yearly, auto-renewing. There is also lifetime access for a one-time €99.99, with no renewal.

The subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple ID account, and you manage the subscription in your account settings. Lifetime access is a one-time purchase and does not renew.

Terms of Use: https://domovina.ai/terms
Privacy Policy: https://domovina.ai/privacy
```

---

## 5. Google Play (EN)

**Short description** (≤80)

```
Transcripts, summaries and analysis of Croatian podcast episodes.
```

**Full description** (≤4000)

Isti tekst kao App Store (EN) opis gore, uz tri izmjene:

1. dodaj stavku `• Use it on Android TV, with the remote` na kraj popisa,
2. zamijeni odlomak o pretplati ovim:

```
Subscription: €4.99 monthly or €39.99 yearly, billed through your Google Play account and renewing automatically. Cancel any time in the Google Play Store under Subscriptions. Lifetime access is a one-time €99.99 purchase and does not renew.
```

3. dodaj AI-disclaimer prije linkova:

```
Episode content comes from publicly published YouTube channels; transcripts, summaries and analysis are generated by AI and may contain errors.
```

---

## 6. Što se smije, a što ne smije pisati o Plusu

Ovo je pravilo, ne stilska preporuka. Nastalo je iz konkretne greške koja je
blokirala store submission.

### ✅ Smije

- Nabrajati **samo** ono što je u tablici iz §1.
- Reći da Plus prije svega **podupire arhivu** — to je pošteno i točno.
- Spomenuti da roadmap postoji, uz izričitu ogradu da nije dio kupnje i da
  nema rok. U listingu je i to bolje **izostaviti** nego riskirati; u appu je
  ograđeno sekcijom „U planu".
- Isticati koliko je toga **besplatno** — to je i marketinški jače i uklanja
  rizik odbijanja tipa „app je neupotrebljiv bez kupnje".

### ⛔ Ne smije — nijedna od ovih rečenica

| Tvrdnja | Zašto je zabranjena |
|---|---|
| „Sinkronizacija na svim uređajima" kao Plus pogodnost | besplatna je svim prijavljenima — naplaćivati je u copyju znači naplaćivati nepostojeću razliku |
| „Preuzimanje epizoda / slušanje bez interneta" | nula koda; ne postoji |
| „Izvoz transkripata i sažetaka (PDF, Markdown, DOCX)" | nula koda; ne postoji |
| „Neograničena semantička pretraga" | ne postoji dnevni limit koji bi se dizao; Plus mijenja **samo** broj rezultata. Sama semantička pretraga **postoji i besplatna je** — netočna je jedino riječ „neograničena", pa se iz opisa ne smije brisati spomen pretrage „po značenju" |
| „Potpuna Magisterium AI analiza" / „uvid u izvore i upite" | Magisterium nije gatean — svi vide isto |
| „Engleski uvijek prvi" / rani pristup prijevodima | ne postoji gate na jeziku |
| „Tvoje ime na zidu zahvale" | pinka zid je vezan na donacije, ne na Plus |
| „Uskoro", „u pripremi", „stiže" uz bilo koju značajku | Apple 2.1 odbija „coming soon" značajke; u opisu nema mjesta za to |

### Provjera prije spremanja u konzolu

1. Svaka rečenica o Plusu ima pandan u tablici §1 ili je uklonjena.
2. `grep -n "sinkroniz\|offline\|izvoz\|export\|neograničen" ` nad tekstom
   koji lijepiš — nula pogodaka izvan konteksta „besplatno je".
3. Cijene u tekstu = cijene u `provisioning-state.md` §2 = cijene u konzoli.
4. Obje varijante (HR i EN) mijenjane u istom prolazu — EN ne smije zaostati
   s tvrdnjom koju je HR već maknuo.
5. Uvjeti i privatnost linkani i **žive** (`/terms`, `/privacy` na domovina.ai).

---

## 7. Screenshotovi i grafike

Ista provjera vrijedi za `store-assets/`. Slika koja prikazuje nepostojeću
funkcionalnost jednako je netočna kao rečenica — i lakše prolazi nezapaženo.

Trenutni set (2026-07-31):

| Mapa | Datoteke |
|---|---|
| `store-assets/ios-iphone/` | 01-home-carousel, 02-magisterium-ai, 03-player-chapters, 04-article, 05-search, 06-channels, 07-channel-detail |
| `store-assets/ios-ipad/` | 01-home, 02-article, 03-search, 04-auth |
| `store-assets/android/` | 01-home-carousel, 02-magisterium-ai, 03-chapters, 04-search, 05-channels, 06-channel-detail, 07-auth |
| `store-assets/play-graphics/` | feature-1024x500, icon-512 |

Sve prikazuju besplatne ekrane — nijedan ne prikazuje paywall. Prije uploada
provjeriti:

- Ne vidi se gumb „Preuzmi", „Izvezi", „Sinkroniziraj" ni bilo što slično.
- Ako se doda screenshot paywalla, mora prikazivati **novi** paywall (tri
  pogodnosti + „U planu" ispod cijena), ne stari.
- Nadpis (caption) na screenshotu podliježe istim pravilima kao opis.

---

## 8. Kad se ovo mijenja

- Kad se doda **prva prava Plus značajka** (prema planu: izvoz sažetka /
  transkripta) — tada se dopunjuje §1, pa opisi, pa konzole, tim redom.
- Kad se mijenja cijena ili se uvede probno razdoblje — §2/§3/§4/§5 odlomci o
  pretplati.
- Kad Apple ili Google promijene obavezne formulacije za pretplate.

Povezano: `TODO-store-launch.md` (što još blokira lansiranje),
`provisioning-state.md` (ID-evi i dokazi), `pricing-and-tiers.md` (cijene —
napomena: tablica pogodnosti u tom dokumentu je **prijedlog iz lipnja** i ne
odgovara stvarnom stanju; mjerodavan je §1 ovdje).
