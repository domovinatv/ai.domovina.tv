# Auth UI/UX — prolaz 2026-07-25 i otvoreni backlog

Zapisnik UI/UX prolaza kroz prijavni flow. Prvi dio je **napravljeno** (živi u
kodu, ovdje samo *zašto*); drugi dio su **nalazi koji NISU implementirani** —
da ne propadnu iz chata.

Povijest ranijih odluka: [`auth-and-database-plan-v3.md`](auth-and-database-plan-v3.md),
`docs/backend-prompts/10-account-management.md`. Registar i lektura: `CLAUDE.md`
(sekcija i18n).

---

## 1. Napravljeno (2026-07-25)

### 1.1 Ukinuti interruptivni onboarding momenti

Obrisani: `lib/onboarding/moments/m1_save_progress_toast.dart`,
`lib/onboarding/moments/m2_link_identity_sheet.dart`,
`lib/onboarding/triggers/watch_seconds_tracker.dart` (+ žice u
`episode_screen.dart` i `episode_simple_screen.dart`).

- **M1** = snackbar „Tvoj se napredak sprema na ovaj uređaj" pri prvom
  otvaranju bilo koje epizode.
- **M2** = auth bottom sheet koji je sam iskakao nakon 30 s aktivne
  reprodukcije.

**Razlog:** modal preko videa nekoliko sekundi nakon starta je hostile —
prekida upravo ono zbog čega je korisnik došao. Snackbar je bio šum bez
akcije. Pravilo koje iz toga slijedi: *auth/upsell nudge nikad ne prekida
reprodukciju; modal se otvara samo na korisnikov tap.*

`AuthSheetOrigin.moment2` → `AuthSheetOrigin.guest`. ARB ključevi
`authM1Toast`, `authHeadlineMoment2`, `authSubMoment2`, `commonMaybeLater`
obrisani iz oba jezika.

`m3_favorite_sync_inline.dart` (snackbar nakon *korisnikovog* tapa na favorit,
s „Sinkroniziraj" akcijom) je **ostao** — to je potvrda radnje, ne interrupt.

### 1.2 Trajna „gost" traka

`lib/widgets/anonymous_signin_bar.dart` — sticky traka u `bottomNavigationBar`
ekrana epizode, isti vizualni jezik kao `PinkaSupportBar` (Material elevation 8,
gornji hairline, ikona + dva reda teksta + filled CTA). Vidljiva samo dok je
`AuthService.instance.isAnonymous`; sluša `AuthService` pa nestane u istom
frameu kad prijava prođe.

Copy: `authGuestBarTitle` / `authGuestBarBody`. Sheet koji otvara ide s
`AuthSheetOrigin.guest` (`authHeadlineGuest` / `authSubGuest`).

Cilj je organski customer acquisition: stalno prisutan, samostalno biran CTA
umjesto interrupta.

### 1.3 Safe-area arhitektura dna ekrana epizode

Prije je svaka traka sama odlučivala hoće li primijeniti donji safe area
(`PinkaSupportBar.applyBottomSafeArea`), a `PinkaSupportBar` se sam sakriva kad
epizoda nema kampanju — pa u kombinaciji „nema kampanje + nema mobilne
navigacije" nitko nije pokrivao notch.

Sada: **jedan vanjski `SafeArea(top: false)` omata cijeli
`bottomNavigationBar` Column**, sve trake unutra idu s
`applyBottomSafeArea: false`, a `SafeArea` iz mobilne nav-trake je uklonjen.
Vrijedi na sva 3 mjesta (`episode_screen` full + basic layout,
`episode_simple_screen`).

**Pravilo:** kad se u `bottomNavigationBar` slaže više traka koje se nezavisno
pale/gase, safe area ide na *kontejner*, nikad na pojedinu traku — inače ili
duplo (dvije sestre svaka primijeni isti inset) ili nula.

### 1.4 Auth sheet — zatvaranje na iOS-u

- `showModalBottomSheet(useSafeArea: true)` + `maxHeight: 92 %` ekrana. Bez
  toga `isScrollControlled` sheet s dugim sadržajem izraste ispod statusne
  trake i **drag handle završi pod Dynamic Islandom** — korisnik ga ne može
  uhvatiti.
- Uvijek dostupan **✕** gore desno; **←** na pod-koracima (e-mail, OTP).
- `PopScope(canPop: !_isSubView)` — sistemski back / swipe na OTP koraku vraća
  korak unatrag umjesto da zatvori cijeli flow (prije se gubio već poslani kôd).
  Isto vrijedi za Esc na desktop dialog varijanti.

### 1.5 Auth sheet — ostatak prolaza

- **Greška/obavijest iznad tile-ova.** Passkey tile je na vrhu; poruka
  renderirana ispod petog providera bila je izvan vidljivog dijela sheeta.
- **Kompaktni header na pod-koracima** (`AuthBrandHeader(compact: true)`) —
  bez logo/wordmark/trikolora bloka. S otvorenom tipkovnicom brand header je
  gurao CTA ispod ruba.
- **Zadnja korištena metoda ide na vrh kao istaknuti tile.** Prije je passkey
  uvijek bio primarni CTA (i onima koji ključ nemaju), a stvarna metoda
  returning usera peta u nizu — glavni uzrok „slučajno sam otvorio drugi
  račun". Fallback bez povijesti ostaje `_defaultOrder`.
- Fokus se vraća u OTP polje nakon pogrešnog koda (`_otpFocus`).
- Tipkovnički fokus na tile-u sad je vidljiv jednako kao hover
  (`onFocusChange` + `focusColor: transparent`) — default InkWell overlay se na
  navy tile-u praktički ne vidi.
- Legal linkovi: `MouseRegion` pointer kursor + 8 px vertikalni padding
  (goli `GestureDetector` u `WidgetSpan`u davao je tap target visine teksta).
- `Semantics(identifier:)` sidra za e2e: `auth-sheet`,
  `auth-provider-<passkey|certilia|google|apple|email>`. Vidi
  [`e2e-testing.md`](e2e-testing.md).
- `_DeleteAccountDialog` → `scrollable: true` (type-to-confirm polje diže
  tipkovnicu, na niskim ekranima je dialog overflowao).

### 1.6 Copy (HR + EN)

- Ujednačen glagolski obrazac kroz sve providere: **„Nastavi …"**. Prije su
  postojala 4 obrasca istovremeno („Prijavi se pristupnim ključem", „Prijava
  eOsobnom", „Nastavi s Googleom", „E-mail magic link").
- `authAnonTitle`: „Niste prijavljeni" → „Još nisi prijavljen·a" (registar
  „ti", vidi `CLAUDE.md`).
- `authProviderEmail`: „Magic link ili kôd na e-mail" → „Poveznica ili kôd na
  e-mail" (bez engleskog u HR copy-ju).
- `authPasskeyTileSub` više ne obećava „najbrže" korisniku koji ključ nema:
  „Face ID ili otisak — ako si ključ već dodao·la".
- `authSubAccount` sada eksplicitno kaže da prvom prijavom nastaje račun
  (prije nigdje nije pisalo da se račun kreira automatski).

### 1.7 Testovi

`test/auth_sheet_test.dart` — vidljivost gost trake za anonimnog korisnika,
postojanje ✕, i korak-natrag s e-mail koraka na providere.

> Napomena: `test/widget_test.dart` (smoke, `HttpClient`) i `test/home_feed_test.dart`
> (datum-ovisan) padaju i na čistom mainu — nisu regresija ovog prolaza.

---

## 2. Otvoreni backlog (NIJE implementirano)

### 2.1 Redoslijed providera vs. konverzija

Fallback redoslijed bez povijesti je **passkey → eOsobna → Google → Apple →
e-mail** (Matijina eksplicitna odluka 2026-06-10, override Apple-first HIG-a).

eOsobna (Certilia/NIAS) je metoda s **najvišim frictionom** — redirect na
vanjski IdP, čitač/mToken, KYC. Držati ju na drugom mjestu je brand statement,
ali je vjerojatno konverzijski skupo za novog korisnika. Za odluku treba mjera
(koliko sheet-otvaranja završi prijavom po metodi), ne debata.

Promjena zahtijeva Matijinu odluku — ne mijenjati bez pitanja.

### 2.2 Brisanje računa ne spominje pretplatu

`authDeleteConfirmBody` nabraja što se briše (račun, favoriti, napredak,
pristupni ključevi, postavke) ali **ne spominje da brisanje računa NE otkazuje
DOMOVINA Plus pretplatu** — ta živi u App Store / Play / RevenueCat i korisnik
ju mora otkazati kroz store.

App Store review to zna tražiti eksplicitno uz Guideline 5.1.1(v). Treba:
- rečenica u `authDeleteConfirmBody` (ili zaseban `authDeleteSubscriptionNote`),
- vidljiva samo kad je `EntitlementService.instance.isPlus` true,
- link na Customer Center / store subscription management.

Vidi [[revenuecat_billing]] memoriju i `RevenueCat:revenuecat-customer-center` skill.

### 2.3 `AccountChip` PopupMenu koristi `ListTile` unutar `PopupMenuItem`

`lib/widgets/account_chip.dart` — `PopupMenuItem(child: ListTile(...))` je
poznat Material anti-pattern: dupli horizontalni inset (PopupMenuItem već ima
svoj) i visina koja ne poštuje `PopupMenuItem.height`. Treba `Row(children:
[Icon, SizedBox(width: 12), Text])`.

Kozmetika, ne blokira ništa.

### 2.4 `AuthCallbackScreen` — 12 s istog spinnera

`lib/screens/auth/auth_callback_screen.dart` vrti identičan spinner do
timeouta. Nakon ~5 s bi trebala doći međuporuka („Ovo traje dulje nego
obično…") da korisnik ne pomisli da je zaglavilo. Trenutno je jedini signal
timeout u 12. sekundi.

### 2.5 Dva paralelna e-mail UI-ja

`showAuthInputDialog` / `_AuthInputDialog` (`lib/onboarding/ui/auth_ui.dart`,
~150 linija) je **živ kod**, ne mrtav — `AuthService._promptForEmail` ga zove s
dva mjesta:

- `linkIdentity(AuthProvider.email)` fallback (kad e-mail flow ne ide kroz
  sheet),
- `_registerPasskey` kad korisnik dodaje passkey a sesija je još anonimna
  (nema e-maila) — npr. „Dodaj pristupni ključ" iz `/account`.

Problem je nedosljednost: isti unos e-maila korisnik vidi jednom kao in-sheet
korak s inline greškama i resend countdownom, a jednom kao stari modalni dialog
bez validacije (regex provjera postoji samo u sheetu — dialog prihvaća bilo
koji string i puca tek na GoTrue odgovoru).

Rješenje: `_registerPasskey` bi trebao voditi kroz isti in-sheet korak, ili
dialog dobiti istu validaciju/error prezentaciju.

### 2.6 Profil nije editabilan

`/account` profil kartica prikazuje ime i e-mail read-only. Nema promjene
display name-a. Van opsega ovog prolaza; zahtijeva backend granu.

### 2.7 Gost traka na desktopu

`AnonymousSignInBar` se prikazuje i na širokim ekranima, gdje home header već
ima „Prijavi se" chip. Namjerno (traka je slim, epizoda je zaseban ekran bez
tog headera), ali ako se pokaže kao šum → gate na `width < 900`.
