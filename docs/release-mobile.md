# Mobile release runbook — App Store (TestFlight) + Google Play (Internal)

Status: pipeline skriptiran end-to-end (build + upload za obje platforme).
Aktualna verzija je u `pubspec.yaml`; skripte je čitaju same.

## Identiteti
- **Bundle / Application ID**: `ai.domovina`
- **Apple Team**: `6SCK58757K` (ITalk d.o.o.) — postavljen u `ios/Runner.xcodeproj/project.pbxproj` i `ios/ExportOptions.plist`.
- **Android signing**: upload keystore `android/upload-keystore.jks`, alias `upload`,
  konfiguracija u `android/key.properties` (oboje gitignored).
  - SHA-1: `F1:5D:B8:2F:AC:6C:F6:4E:20:C5:BF:F8:5C:45:A9:42:EC:AA:F7:4E`
  - SHA-256: `F6:2C:30:D2:83:FB:BF:E4:B4:2C:51:AC:A8:08:AD:94:55:FB:1E:78:94:72:D9:30:73:96:AE:05:67:13:A1:3A`
  - **BACKUP keystore + lozinku van repoa — gubitak = nema update bez Play App Signing reseta.**

## Build (lokalno)
```bash
./scripts/build-mobile-release.sh android   # AAB → build/app/outputs/bundle/release/app-release.aab
./scripts/build-mobile-release.sh ios        # IPA  → build/ios/ipa/*.ipa (treba ITalk signing)
```
Embeda `--dart-define` (SUPABASE_URL/ANON_KEY, MEILI_URL…) iz `.env`.

## Android → Google Play (Internal testing)
1. Play Console → Create app: name "DOMOVINA.ai", default lang HR, App, Free.
2. Potpiši Developer agreement. Uključi **Play App Signing** (preporučeno; upload key = naš keystore).
3. Testing → Internal testing → Create release → upload `app-release.aab`.
4. Dodaj testere (email lista / Google Group), spremi, Review & rollout.
5. Za produkciju: Dashboard "Set up your app" — Data safety, Content rating
   (IARC upitnik), Target audience, Privacy policy URL, store listing
   (ikona 512, feature graphic 1024×500, min 2 screenshota), pa Production track.

## iOS → App Store Connect (TestFlight)
Preduvjeti: App ID `ai.domovina` registriran + App record u App Store Connect
pod ITalk teamom + ITalk signing pristup (API key ili Xcode account).

### Export + upload preko API key (CLI)
```bash
# 1. build IPA (clean → config-only → xcodebuild archive → exportArchive,
#    sve s ASC API key; `flutter build ipa` NE radi — pada na exportu)
./scripts/build-mobile-release.sh ios
# 2. upload na TestFlight
./scripts/testflight-upload.sh
```
Ručne xcodebuild/altool komande (ako treba debug pojedinog koraka) su u
`scripts/build-mobile-release.sh` i `scripts/testflight-upload.sh`.
API key se generira u App Store Connect → Users and Access → Integrations →
App Store Connect API → ključ rola App Manager. `.p8` ide u
`~/.appstoreconnect/private_keys/` ili se referencira putanjom.

### Produkcija (App Store review)
App Store Connect → app → 1.0 verzija: opis, keywords, support URL, marketing
URL, screenshotovi (6.7" + 6.5" iPhone, min 1 set), App Privacy (data types:
account/auth, identifiers), age rating, build odabran iz TestFlighta → Submit
for Review.

## Napomene / TODO
- iOS launch image je još default placeholder (warning pri buildu, ne blokira
  review ali zamijeniti za kvalitetu).
- Android App Links (`autoVerify`) traže `/.well-known/assetlinks.json` na
  domovina.ai sa SHA-256 **Play App Signing** ključa (ne upload ključa) nakon
  enrollmenta — inače deep linkovi ne verificiraju.
