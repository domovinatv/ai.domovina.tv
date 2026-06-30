# Internationalization & Localization (i18n)

> Kako DOMOVINA.ai lokalizira korisničko sučelje. Hrvatski je izvorni jezik,
> engleski drugi. Sustav je uveden 2026-07 punom ekstrakcijom ~756 stringova
> kroz ~50 datoteka na Flutter `gen-l10n` (ARB).
>
> Sažeta verzija pravila živi u `CLAUDE.md` (sekcija "Internationalization");
> ovaj dokument je puna referenca s dijagramima.

---

## 1. Dva jezika, dva sustava — UI jezik ≠ jezik sadržaja

Najvažniji koncept. Aplikacija ima **dva neovisna** jezična sloja koja se lako
pobrkaju:

```mermaid
flowchart TB
    subgraph UI["🧭 UI JEZIK (chrome)"]
        direction TB
        U1["Gumbi, naslovi, tooltipovi,<br/>SnackBar/dialog poruke, prazna stanja"]
        U2["Bira: LocaleController<br/>(services/locale_service.dart)"]
        U3["Izvor: lib/l10n/app_hr.arb + app_en.arb<br/>→ AppLocalizations"]
        U1 --- U2 --- U3
    end
    subgraph CONTENT["📄 JEZIK SADRŽAJA (per-epizoda)"]
        direction TB
        C1["Članak, transkript, Magisterium analiza,<br/>sažetak — tekst koji je AI generirao"]
        C2["Bira: EpisodeLanguage + language_toggle_chip<br/>(services/episode_language.dart)"]
        C3["Izvor: CDN JSON<br/>article.json / article.en.json,<br/>*.magisterium*.json / *.magisterium*.en.json"]
        C1 --- C2 --- C3
    end
    UI -. "potpuno odvojeno" .- CONTENT

    style UI fill:#002F6C,color:#fff
    style CONTENT fill:#7a1020,color:#fff
```

| | UI jezik (chrome) | Jezik sadržaja (per-epizoda) |
|---|---|---|
| **Što** | Gumbi, oznake, poruke | AI-generirani članak/Magisterium/sažetak |
| **Kontroler** | `LocaleController` | `EpisodeLanguage` + `LanguageToggleChip` |
| **Izvor teksta** | ARB (`app_*.arb`) | CDN JSON (`*.json` / `*.en.json`) |
| **Doseg** | Cijela aplikacija | Jedan ekran epizode |
| **Lokalizira se kroz ARB?** | **DA** | **NE** — `pickLang(...)` bira CDN varijantu |

> **Pravilo**: CDN/model tekst se NIKAD ne lokalizira kroz ARB. U ARB idu samo
> **hardkodirani** Dart literali. Ako je rečenica došla s `cdn.domovina.ai`,
> to nije app string.

---

## 2. Razrješavanje stringa (string resolution)

Kako kod dođe do prevedenog teksta — ovisi ima li `BuildContext`:

```mermaid
flowchart TD
    Start["Trebam prikazati tekst korisniku"] --> HasCtx{"Imam li<br/>BuildContext?"}

    HasCtx -->|"DA (widget build,<br/>metoda s contextom)"| Ctx["final l = AppLocalizations.of(context)"]
    Ctx --> CtxUse["l.mojKljuc"]

    HasCtx -->|"NE (servis, callback,<br/>model, top-level)"| NoCtx["appStrings (globalni getter,<br/>services/locale_service.dart)"]
    NoCtx --> Lookup["lookupAppLocalizations(<br/>LocaleController.instance.locale)"]
    Lookup --> NoCtxUse["appStrings.mojKljuc"]

    CtxUse --> ARB[("app_hr.arb / app_en.arb<br/>→ AppLocalizations")]
    NoCtxUse --> ARB

    style Ctx fill:#1f6f3f,color:#fff
    style NoCtx fill:#8a5a00,color:#fff
    style ARB fill:#002F6C,color:#fff
```

- **U widgetu** (ima context): `AppLocalizations.of(context)`. Prati `Localizations`
  scope; ispravno reagira na promjenu jezika.
- **Bez contexta** (servisi, modeli, async callbackovi): globalni `appStrings`
  getter. Interno `lookupAppLocalizations(LocaleController.instance.locale)` —
  ne treba widget tree.

```dart
// widget
final l = AppLocalizations.of(context);
return Text(l.homeSearchTooltip);

// servis / bez contexta
import '.../services/locale_service.dart';
throw AuthFailure(appStrings.serviceSignInFailed);
```

---

## 3. Odabir i perzistencija jezika

```mermaid
flowchart LR
    subgraph Persist["Perzistencija"]
        LS["Web: window.localStorage<br/>('app_locale')"]
        SP["Native: SharedPreferences<br/>('app_locale')"]
    end
    LC["LocaleController<br/>(ChangeNotifier, default 'hr')"]
    Persist --> LC

    LC --> Merge["Listenable.merge([<br/>ThemeController, LocaleController])"]
    Merge --> MA["MaterialApp.router<br/>locale: …instance.locale<br/>localizationsDelegates / supportedLocales"]

    subgraph Switchers["Prebacivači (vidljivi svima, i anon)"]
        SW1["Home app bar<br/>(widgets/language_toggle_button.dart)"]
        SW2["/account ekran<br/>(SegmentedButton HR/EN)"]
    end
    Switchers -->|"setLocale(Locale)"| LC

    TV["Android TV grana"] -->|"locale: const Locale('hr')<br/>(fiksno, 10-foot UI)"| MA

    style LC fill:#002F6C,color:#fff
    style MA fill:#1f6f3f,color:#fff
```

- `main.dart` poziva `LocaleController.instance.init()` prije `runApp` (uz
  `ThemeController.init()`).
- Mobile/web `MaterialApp.router` sluša `Listenable.merge([Theme, Locale])` pa se
  rebuilda na promjenu jezika; `locale: LocaleController.instance.locale`.
- **Android TV** je fiksno `Locale('hr')` (jedno tržište, 10-foot UI) — i dalje
  prolazi delegate da EN postoji u buildu.
- **Default**: hrvatski (novi korisnik bez spremljene vrijednosti).
- **Imena jezika u prebacivačima su endonimi** ("Hrvatski"/"English") — NAMJERNO
  neprevedena, da ih korisnik prepozna neovisno o aktivnom jeziku. NISU u ARB-u.

---

## 4. Konfiguracija i datoteke

```mermaid
flowchart TD
    YAML["l10n.yaml<br/>template-arb-file: app_hr.arb<br/>output-dir: lib/l10n<br/>nullable-getter: false"]
    HR["lib/l10n/app_hr.arb<br/>(IZVORNI/template + @key metapodaci)"]
    EN["lib/l10n/app_en.arb<br/>(prijevod)"]
    GEN["flutter gen-l10n<br/>(ili generate: true pri buildu)"]
    OUT["lib/l10n/app_localizations.dart<br/>app_localizations_hr.dart<br/>app_localizations_en.dart"]

    YAML --> GEN
    HR --> GEN
    EN --> GEN
    GEN --> OUT
    OUT --> APP["AppLocalizations.of(context)<br/>+ lookupAppLocalizations()"]

    style HR fill:#002F6C,color:#fff
    style OUT fill:#1f6f3f,color:#fff
```

| Datoteka | Uloga |
|---|---|
| `l10n.yaml` | Konfiguracija gen-l10n |
| `lib/l10n/app_hr.arb` | **Izvorni** jezik + `@key` metapodaci (description, placeholders, ICU plural) |
| `lib/l10n/app_en.arb` | Engleski prijevod (samo vrijednosti) |
| `lib/l10n/app_localizations*.dart` | **Generirano** — ne uređuj ručno |
| `lib/services/locale_service.dart` | `LocaleController` + `appStrings` getter |
| `pubspec.yaml` | `flutter_localizations`, `intl: any`, `generate: true` |

---

## 5. Konvencija imenovanja ključeva (key prefixes)

Svaki ključ ima prefiks područja. Time se izbjegava kolizija i lako se grupira.
(Tijekom inicijalne migracije svaki je paralelni agent imao svoj prefiks → 0
kolizija pri spajanju 756 ključeva.)

```mermaid
mindmap
  root((ARB ključevi))
    common*
      "dijeljeno: Odustani, Zatvori,<br/>Pokušaj ponovno, Greška…"
    home*
    episode*
    section*
      "članak/sažetak/poglavlja/govornici"
    magisterium*
    media*
      "video/player/favorit/tema"
    auth*
      "account + onboarding + prijava"
    channel*
      "kanal/pretraga/paywall/booking"
    legal*
    ownership*
    tv*
    pinka*
    service*
      "servisne poruke (appStrings)"
```

- `common*` — stringovi dijeljeni kroz aplikaciju; provjeri postoji li prije nego
  dodaš novi.
- ICU plural za brojive imenice (hrvatski **one/few/other**), npr.
  `{count, plural, one{...} few{...} other{...}}`.
- Placeholderi: `{name}`, `{count}`, `{date}` — definirani u `@key.placeholders`.

---

## 6. Kako dodati novi string (recept)

```mermaid
flowchart LR
    A["1. Dodaj ključ u app_hr.arb<br/>(+ @key ako ima placeholder/plural)"]
    B["2. Dodaj prijevod u app_en.arb"]
    C["3. flutter gen-l10n"]
    D["4. Koristi u kodu:<br/>l.kljuc ILI appStrings.kljuc"]
    E["5. flutter analyze"]
    A --> B --> C --> D --> E
```

1. **Uvijek prvo HR** (izvorni jezik), pa EN.
2. Prefiks po području; `common*` ako je dijeljeno.
3. `flutter gen-l10n` (ili samo build — `generate: true`).
4. Widget → `AppLocalizations.of(context)`; bez contexta → `appStrings`.

---

## 7. Registar i lektura (brand voice)

> **Pravilo (ton)**: aplikacija oslovljava korisnika **neformalno „ti"** — topao,
> izravan glas, usklađen s pinka SDK-om. **Iznimka**: outreach poruke trećim
> stranama (npr. `ownershipInviteMessage` — poruka vlasniku kanala kojeg ne
> poznaješ) i pravni/formalni tekst → tu je „Vi" ispravno. Ne miješaj registar
> unutar istog konteksta.

> **Pravilo (lektor)**: svaki user-facing string ima ispravne dijakritike
> (č/ć/š/ž/đ), gramatiku i pravopis po **Hrvatskom pravopisu IHJJ**
> ("sažetci", "pogreške", "adresa e-pošte" ne "email adresa"). Deanglicizacija gdje
> postoji prirodna hrvatska riječ ("ocjena" ne "score"). **Bez ALL-CAPS u ARB
> vrijednostima** — vizualni caps radi se u kodu preko `.toUpperCase()` na već
> lokaliziranom stringu. Hrvatski navodnici „…".

---

## 8. Magisterium dijakritike — analiza uzroka

Korisnik je prijavio Magisterium rečenice bez dijakritika ("Sto je rekao…").
Uzrok je **dvojak** i kritično ih je razlikovati:

```mermaid
flowchart TD
    Q["Magisterium tekst bez dijakritika"] --> T{"Je li to cijela<br/>rečenica analize<br/>ili statična oznaka?"}

    T -->|"Statična oznaka<br/>('Teoloska analiza',<br/>'Uglavnom uskladjeno')"| APP["APP BUG ✅ popravljeno"]
    APP --> APPfix["Hardkodirani Dart literal →<br/>lokaliziran + ispravne dijakritike<br/>(magisterium_section/article_section/panel)"]

    T -->|"Rečenica analize<br/>('Sto je rekao…',<br/>assessment/evaluation)"| CDN["CDN/PIPELINE PROBLEM ⚠️"]
    CDN --> CDNfix["Čita se DOSLOVNO iz<br/>*.magisterium*.json na CDN-u.<br/>App je netaknut. Rješava se iz<br/>fetch.domovina.tv repoa (regeneracija)."]

    style APP fill:#1f6f3f,color:#fff
    style CDN fill:#8a5a00,color:#fff
```

- **App-side (popravljeno ovdje)**: statične oznake bile su pisane bez dijakritika
  → sada lokalizirane i ispravne ("Teološka analiza", "Usklađenost s katoličkim
  naukom i Svetim pismom", "Uglavnom usklađeno"…).
- **CDN-side (NIJE app bug)**: same rečenice analize (`assessment`, `enrichment`,
  `concerns`, `evaluation`, `score_interpretation`) dolaze s CDN-a preko
  `pickLang(...)`. Popravak = regeneracija pipeline-a iz `fetch.domovina.tv`
  (Magisterium = MCP-only; vidi feedback pravilo o radu iz fetch repoa).

---

## 9. Proces inicijalne migracije (povijesno)

Migracija ~756 stringova izvedena je paralelno, fan-out po području, da se izbjegne
ručni serijski rad i konflikti:

```mermaid
flowchart TB
    F["Temelj: l10n.yaml, ARB skeleton,<br/>LocaleController, appStrings, common*"]
    F --> Fan{"12 paralelnih agenata<br/>(disjunktne datoteke,<br/>jedinstveni key-prefiks)"}
    Fan --> A1["home"]
    Fan --> A2["episode / section / magisterium / media"]
    Fan --> A3["auth / channel / legal / ownership"]
    Fan --> A4["tv / pinka / service"]
    A1 --> Frag["frag_*.json fragmenti<br/>(hr + en + desc + placeholders)"]
    A2 --> Frag
    A3 --> Frag
    A4 --> Frag
    Frag --> M["merge skripta → app_hr.arb + app_en.arb<br/>(0 kolizija, 0 missing EN)"]
    M --> G["flutter gen-l10n + analyze + build --wasm"]

    style F fill:#002F6C,color:#fff
    style M fill:#1f6f3f,color:#fff
    style G fill:#1f6f3f,color:#fff
```

Ključ uspjeha: **jedinstveni prefiks po agentu** (nema kolizije ključeva) +
**disjunktni skupovi datoteka** (nema konflikta editova) + **fragment-datoteke**
umjesto dijeljenog ARB-a (nema race na zapisivanju). Spajanje je deterministička
skripta.

---

## 10. Poznati TODO-ovi

- **Datumi (mjeseci/dani)**: `widgets/founder_booking.dart` koristi ručne hrvatske
  nizove naziva (`_hrWeekdayShort`, `_hrMonthsGen`). Za pravu lokalizaciju datuma
  treba `intl` `DateFormat` s locale podrškom (bilo je van opsega string-ekstrakcije).
- **CDN Magisterium/članci**: lokalizacija sadržaja je odvojen pipeline posao
  (`fetch.domovina.tv`), ne app.
- **Pretvaranje preostalih ALL-CAPS dizajna**: gdje dizajn traži velika slova,
  vrijednost ostaje normal-case u ARB-u, a `.toUpperCase()` se primjenjuje u kodu.

---

## 11. Brza referenca

```dart
// 1. Widget s contextom
final l = AppLocalizations.of(context);
Text(l.homeSearchTooltip);
Text(l.commonRetry);
Text(l.sectionAgeDays(daysCount));            // ICU plural

// 2. Bez contexta (servis/model/callback)
import '.../services/locale_service.dart';
SnackBar(content: Text(appStrings.serviceSignedInAs(name)));

// 3. Promjena jezika
LocaleController.instance.setLocale(const Locale('en'));
LocaleController.instance.toggle();           // HR ↔ EN

// 4. Regeneracija nakon uređivanja ARB-a
//    flutter gen-l10n   (ili samo flutter build — generate: true)
```
