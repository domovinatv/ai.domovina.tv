# Splash screen — biblijski citati

DOMOVINA.ai splash screen prikazuje biblijski citat tijekom hladnog starta
aplikacije. Postoje **dva splash sloja** — native Android i Flutter-rendered.

---

## ⚠️ UPDATE 2026-05-28 — Premium full-frame overhaul (supersedes below)

Velika revizija. Ključne promjene koje **nadjačavaju** stariji opis ispod:

### Arhitektura
- **Native splash je sada premium full-frame 4K PNG** (`splash_full_1.png`,
  3840×2160), ne više layer-list (logo + tagline band). Generiran preko
  `scripts/generate-premium-splash-taglines.py` (PIL auto-fit tipografija).
- **Flutter boot splash = `TvBootSplash` widget** prikazuje **identičnu**
  sliku (`assets/splash/splash_full_1.png`) + diskretni "Učitavanje…"
  progress na dnu. Cilj: vizualni kontinuitet — native→Flutter handoff bez
  frame promjene. Zamijenio `TvLoadingTips` u boot pathu (TvLoadingTips
  ostaje u kodu, neiskorišten u bootu).
- **Flash fix**: `NormalTheme.windowBackground` = `LaunchTheme.windowBackground`
  = `@drawable/launch_background`. Bez toga theme swap stvara crni bljesak.
  Vidi memory `feedback_splash_theme_continuity`.

### Trajanje (ISPRAVAK)
Native splash je vidljiv **~2.1s**, NE 12-19s. Stari "12-19s" je bio
percipirani Flutter loading period (ChannelCache prefetch). Cold start
detalji: `docs/android-tv-performance.md`.

### Citati — KS Jeruzalemska Biblija (NE više Magisterium AI raw)
Svi citati su **fact-checkani protiv https://biblija.ks.hr** (službeni
hrvatski liturgijski tekst koji se čita na misi). 10/14 Magisterium AI
tekstova se razlikovalo i zamijenjeno je KS verzijama. Detaljni diff:
`docs/splash-bible-citations-factcheck.md`. Najvažniji fix: Mt 9,37
"Žetva je velika, ali radnika malo" → KS "Žetve je mnogo, a radnikâ malo".

- **Native splash citat**: Mt 10,26-**27** (skraćeno s 26-28 jer ~2s+10s
  loading ne ostavlja vremena za 3 retka).
- **Flutter rotacija**: 13 KS citata u `defaultBibleVerses`
  (`tv_loading_tips.dart`) — ostaje za eventualni reuse.

### Generiranje
- `scripts/generate-premium-splash-taglines.py` — PIL auto-fit, default
  generira samo `splash_full_1` (production), `--all` za svih 14 (design
  review). Mirror u `assets/splash/` za Flutter.
- `assets/icons/splash-template.svg` — layout source-of-truth (design
  artifact; renderer mora odražavati promjene).
- Fontovi: `assets/fonts/{Lora-Italic, Inter-Bold, Inter-Regular}.ttf`
  (Lora Italic za citat, Inter za wordmark/atribuciju — vidi memory
  `feedback_splash_typography`).
- Stari `splash_tagline_*.png` + `splash_logo.png` OBRISANI (cleanup,
  ~5MB AAB ušteda).

---

## Pregled (povijesno — vidi update iznad za trenutno stanje)

| Sloj | Trajanje | Sadržaj | Rotacija |
|---|---|---|---|
| **Native Android splash** | ~12-19 s na sporijem TV hardveru | Logo + Matej 10,26-28 (kompletni odlomak) | ❌ Static (vidi ispod) |
| **Flutter loading splash** | ~3-10 s (ChannelCache prefetch) | Random biblijski citat + rotirajuće tips + 10s progress bar | ✅ Random per launch |

## Kuracija citata

Citate je preporučio **Magisterium AI** (https://www.magisterium.com), AI
asistent specijaliziran za katoličko učenje. Curation odgovara identitetu
aplikacije: AI-obrada hrvatskih katoličkih podcasta s ciljem da "ništa
skriveno ne ostane skriveno" — istina sadržaja postaje pretraživa,
povezana s učenjem Crkve, i dostupna svima.

### Native splash (kompletni Matej 10,26-28)

Pošto se native splash ne može rotirati na Android <12 (vidi sekciju
"Tehnička arhitektura" niže), korisnik ga čita do 19 s. Magisterium AI
preporučio je proširenje na 3 retka (26-28) da daju puni smisao:

> "Ne bojte ih se dakle. Ta ništa nije skriveno što se neće otkriti ni tajno
> što se neće doznati. Što vam govorim u tami, recite na svjetlu; i što na
> uho čujete, propovijedajte na krovovima. Ne bojte se onih koji ubijaju
> tijelo, ali duše ne mogu ubiti. Bojte se više onoga koji može i dušu i
> tijelo pogubiti u paklu."
>
> — **Matej 10,26-28**

**Zašto baš ovaj odlomak za DOMOVINA.ai:**
1. **"Propovijedajte na krovovima"** (Mt 10,27) — savršena metafora za
   moderne podcaste. Ono što se nekada govorilo u uskim krugovima ili "u
   tami", danas se digitalnim platformama odašilje s "krovova".
2. **Hrabrost pred svijetom** (Mt 10,28) — moralna vertikala. Integritet
   duše i vjernost istini važnija od društvenog ili političkog pritiska.
3. **Težina i duljina teksta** — ispunjava ekran i zadržava pažnju
   tijekom ~20 s učitavanja, daje materijal za kratko razmatranje.

### Flutter splash (14 kratkih citata)

Flutter splash random pickne **jedan citat per launch** (drži ga za sav
loading session, ne rotira tokom session-a — to bi bilo previše pokreta uz
rotirajuće tips). Implementiran u `lib/screens/tv/widgets/tv_loading_tips.dart`
kao `defaultBibleVerses` lista. Kratki Mt 10,26 izostavljen je iz Flutter
liste jer ga je korisnik upravo gledao 12-19 s na nativnom splashu.

**Tri kategorije citata** (13 ukupno u Flutter rotaciji):

#### Temeljni o istini i razotkrivanju (3)
- **Marko 4,22** — "Jer ništa nije tajno osim da bi se očitovalo…"
- **Luka 8,17** — "Ta ništa nije tajno što se neće očitovati…"
- **Luka 12,2** — "Ništa nije prikriveno što se neće otkriti…"

#### Identitet aplikacije (1)
- **Filipljanima 3,20** — "Naša je pak domovina na nebesima…"

#### Isusove izreke o hrabrosti i prioritetima (9)
- **Ivan 8,32** — "Upoznat ćete istinu i istina će vas osloboditi."
- **Matej 5,37** — "Vaša riječ neka bude: 'Da, da – ne, ne!'…"
- **Ivan 16,33** — "U svijetu ćete imati muku, ali hrabri budite…"
- **Matej 6,21** — "Gdje ti je blago, ondje će ti biti i srce."
- **Matej 6,33** — "Tražite stoga najprije Kraljevstvo Božje…"
- **Ivan 14,6** — "Ja sam Put i Istina i Život…"
- **Matej 22,21** — "Podajte dakle caru carevo, a Bogu Božje."
- **Matej 9,37** — "Žetva je velika, ali radnika malo."
- **Luka 6,45** — "Iz obilja srca usta mu govore."

## Tehnička arhitektura

### Native Android splash — zašto je static

**Pokušali smo runtime rotaciju 4 različita pristupa, svi su FAILED na
Android <12** (EON SDSTB02 je API 30):

1. **`setTheme(LaunchTheme_N)` u `MainActivity.onCreate` PRIJE
   `super.onCreate`** — counter rotira ispravno (potvrđeno logcat-om), ali
   vizualni splash uvijek pokazuje variant 1.

2. **`window.setBackgroundDrawableResource(R.drawable.launch_background_N)`
   POSLIJE `super.onCreate`** — isto kao gore, vizualno bez efekta.

3. **`window.decorView.background = drawable` + `decorView.invalidate()`**
   — bulletproof multi-path override, isto bez vizualnog efekta.

4. **Theme attribute reference (`?attr/splashTagline` + 14 LaunchTheme_N
   stilova svaki override-a attr na drugu PNG)** — atribut se resolva u
   trenutku theme aplikacije, što bi teoretski trebalo raditi… ali ne.

**Root cause:** Android "starting window" (preview drawn by SystemUI prije
nego Activity pokrene) koristi MANIFEST theme bez ikakvog runtime override-a
i persistira do prvog Activity content frame-a. Pošto Flutter traje
12-19 s da nacrta prvi frame, starting window ostaje cijelo vrijeme. Naš
runtime setTheme/setBackground nikad ne dobije vizualni efekt.

5. **`<item name="android:windowDisablePreview">true</item>`** — ovo je
   tehnički "fix" ali daje **crni ekran 12-19 s** umjesto splash-a. Bez
   starting window-a, Activity Window se ne pojavi dok ga Flutter prvi
   frame ne triggera.

**Android 12+ (API 31+) SplashScreen API** bi omogućio runtime customizaciju
— ali EON je API 30. `androidx.core:splashscreen` backport library bi to
omogućio i na nižim verzijama, ali bi zahtijevao značajan refactor manifest
theme strukture. Trenutno odluka: ne uvodimo dodatnu dependency.

#### Retest verifikacija (2026-05-27)

Originalna istraga oslanjala se na ADB `screencap` koji je vraćao crni PNG
i za splash i za launcher home screen. Nakon što je korisnik uključio
Philips TV (HDMI sink), screencap je proradio (Amlogic Surface\-Flinger
ne compose-a framebuffer bez aktivnog sink-a).

Pristup #1 (setTheme prije super.onCreate) ponovno je testiran s
hardcoded targetom `LaunchTheme_7` i tagline_7 PNG-om. Logcat potvrdio
da je `setTheme(LaunchTheme_7)` izvršen prije super.onCreate, ali
screencap je svejedno prikazao **default tagline_1**. Md5 hash identičan
s prijašnjim screencap-ovima koji nemaju setTheme — zero visual impact.

Verdict iz originalne istrage je **potvrđen pravim screencap-om**.
Starting window se kompozit-a iz manifesta i ne reagira na runtime
override. Sva 5 pristupa dijele isti fundamentalni problem.

### Static native implementacija

```
android/app/src/main/res/
├── drawable/
│   ├── launch_background.xml      ← layer-list: bg color + logo + tagline
│   └── splash_logo.png            ← copy of assets/icons/domovina_ai_logo_1024.png
├── drawable-v21/
│   └── launch_background.xml      ← isto (Android 5.0+ override)
├── drawable-nodpi/
│   └── splash_tagline_1.png       ← Mt 10,26-28 (Times New Roman Italic, 1600×620)
│   └── splash_tagline_{2..14}.png ← za Flutter (ali nisu korišteni native)
├── values/
│   ├── colors.xml                 ← splash_bg = #002F6C (Croatian navy)
│   └── styles.xml                 ← LaunchTheme + NormalTheme
└── values-night/
    └── styles.xml                 ← dark variant — identično trenutno
```

`launch_background.xml` layer-list:
```xml
<layer-list>
    <item drawable="@color/splash_bg" />                    <!-- Croatian navy -->
    <item width=180dp height=180dp gravity=top top=60dp
          drawable="@drawable/splash_logo" />                <!-- wordmark -->
    <item width=900dp height=280dp gravity=bottom bottom=30dp
          drawable="@drawable/splash_tagline_1" />           <!-- Mt 10,26-28 PNG -->
</layer-list>
```

`MainActivity.kt` — minimal, bez splash logike (rotacija nije moguća):
```kotlin
class MainActivity : AudioServiceActivity() {
    // Samo TV mode method channel + audio_service.
}
```

### Flutter splash — rotacija

`lib/screens/tv/widgets/tv_loading_tips.dart` widget:
- `defaultBibleVerses` const lista (13 citata)
- `_TvLoadingTipsState.initState` random-pickne jedan koristeći `Random()`
- Verse drži se za sav loading session (nije periodična rotacija)
- Layout: Stack — verse na vrhu (32% ekrana), tips u centru, progress bar dno

`lib/screens/tv/tv_home_screen.dart` koristi ovo:
```dart
Widget _buildLoading(ThemeData theme, double heroHeight) {
  return const TvLoadingTips(
    tips: defaultTvTips,
    progressDuration: Duration(seconds: 10),
  );
}
```

`_bootReady` flag drži loading state vidljiv sve dok:
1. Channel index ucitan
2. `_channelCache.done` (svih 40 kanala prefetchano)
3. `HomeFeed.pickFeatured` vrati non-null
4. Featured thumbnail preload-an (`precacheImage`)

Tek tad UI prebaci s loading na pravi content — sprjecava "double flash"
(prazan hero skeleton → popunjen hero).

## PNG generiranje

Tagline PNG-evi generirani su ImageMagick-om s Times New Roman Italic
fontom. Skripta nije pridruzena (one-shot bash one-liner) — pri buducim
izmjenama citata pokreni rucno ili izvuci u `scripts/generate-splash-taglines.sh`:

```bash
FONT_VERSE='/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf'
FONT_REF='/System/Library/Fonts/Supplemental/Times New Roman.ttf'

VERSE='"verse text"'
REF='— Reference'

magick \
  \( -background transparent -font "$FONT_VERSE" -pointsize 34 \
     -fill 'rgba(255,255,255,0.97)' -size 1500x -interline-spacing 6 \
     caption:"$VERSE" \) \
  \( -background transparent -size 1500x32 xc:transparent \) \
  \( -background transparent -font "$FONT_REF" -pointsize 28 \
     -fill 'rgba(255,255,255,0.72)' -size 1500x caption:"$REF" \) \
  -background transparent -gravity center -append \
  -gravity center -extent 1600x620 \
  -type TrueColorAlpha \
  -define png:color-type=6 \
  PNG32:splash_tagline_1.png
```

PNG-evi su u `drawable-nodpi/` da ih Android ne skalira po density bucketu;
veličinu kontroliramo eksplicitno u layer-list `<item width/height>`.

## Reference

- [Matej 10:24-33](https://www.magisterium.com/docs/7ab6e175-afab-4262-915a-0e98ce0d133d/ref/Matthew%2010:24-10:33) — primarni native citat
- [Marko 4:22](https://www.magisterium.com/docs/7ab6e175-afab-4262-915a-0e98ce0d133d/ref/Mark%204:22)
- [Luka 8:17](https://www.magisterium.com/docs/7ab6e175-afab-4262-915a-0e98ce0d133d/ref/Luke%208:17)
- [Luka 12:2](https://www.magisterium.com/docs/7ab6e175-afab-4262-915a-0e98ce0d133d/ref/Luke%2012:2)
- [Filipljanima 3:20](https://www.magisterium.com/docs/7ab6e175-afab-4262-915a-0e98ce0d133d/ref/Philippians%203:20)

Hrvatski tekst preuzet iz tradicionalnog hrvatskog prijevoda Biblije
(jeruzalemski tekst, izdanje Kršćanske sadašnjosti).

## Buduća pobošljanja

- **Android 12+ SplashScreen API**: kad/ako bude vrijedno, integrirati
  `androidx.core:splashscreen` library za pravu runtime rotaciju i na
  starijim Android verzijama. Trade-off: dodatna dependency.
- **TV-specific resource qualifier** (`drawable-television/`): za striktnije
  TV-optimizirane dimenzije ako kasnije bude problema na portret mobitelu.
- **Scripts**: `scripts/generate-splash-taglines.sh` da generiranje PNG-eva
  bude reproducibilno i checked-in (umjesto bash one-liner-a u commit messageu).
