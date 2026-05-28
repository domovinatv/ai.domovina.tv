# Lokalni Android TV emulator (EON-matched)

Brzi dev loop za `lib/screens/tv/` na Mac miniju bez ovisnosti o fizičkom EON
boxu preko Tailscale-a. Emulator vjerno reproducira **EON geometriju** i
auto-detektira se kao Leanback TV, pa app ulazi u TV mod bez `--dart-define=FORCE_TV`.

## Čemu služi (i čemu NE)

| Dobro za | NE valja za |
| --- | --- |
| Layout / overflow na EON density (960×540 dp) | Mjerenje performansi / janka |
| D-pad navigacija (strelice = D-pad, Enter = OK) | GPU throttling reprodukcija |
| Leanback auto-detekcija, theme, fokus | AV1 hwdec ponašanje (codec se razlikuje) |
| Brži ciklus od ADB-over-Tailscale na box | — |

**Zašto perf ne valja:** emulator koristi GPU Mac minija + nativni arm64 CPU, pa
je sve glatko. EON jank je raster/GPU-bound na slabom Amlogicu (zato je Impeller
ugašen, vidi `docs/android-tv-performance.md`). **Perf mjeriš samo na fizičkom
EON-u.**

## Što je postavljeno

- **AVD `EON_TV_API31`** — image `system-images;android-31;android-tv;arm64-v8a`
  (Android 12; arm64 TV image ne postoji za API 30 / Android 11 — ovo je najbliži
  upotrebljiv, x86 image bi na Apple Siliconu bio neupotrebljivo spor).
  - 1920×1080 @ 320dpi → 960×540 dp (točno EON), 2GB RAM, D-pad, landscape, non-touch.
- **Storage na vanjskom 2TB SSD-u.** SSD je exFAT (loš za Android SDK: nema POSIX
  permissions/symlinkove, `fskit` driver vraća lažni "No space left"). Rješenje:
  **APFS sparsebundle kontejner** kao file unutar exFAT-a:
  - Kontejner: `/Volumes/DOMOVINA2TB/android_emulators/DOMOVINA_ANDROID.sparsebundle`
  - Mounta se kao: `/Volumes/DOMOVINA_ANDROID` (pravi POSIX APFS volumen)
  - `~/Library/Android/sdk/system-images` → symlink na kontejner
  - `~/.android/avd/EON_TV_API31.ini` → symlink na AVD u kontejneru

## Svakodnevni workflow

```bash
# 1. Mountaj APFS kontejner (poslije reboota Maca NIJE auto-mountan)
hdiutil attach /Volumes/DOMOVINA2TB/android_emulators/DOMOVINA_ANDROID.sparsebundle

# 2. Upali emulator
~/Library/Android/sdk/emulator/emulator @EON_TV_API31 &
#   (alt: flutter emulators --launch EON_TV_API31)

# 3. Pokreni app — često su 2 uređaja spojena (emulator + fizički), pa targetiraj eksplicitno
flutter run -d emulator-5554

# Screenshot
adb -s emulator-5554 exec-out screencap -p > /tmp/eon.png
```

D-pad u emulatoru: strelice na tipkovnici = smjer, Enter = OK/select, Esc = back.

## Rezolucija na emulatoru

Emulator crta u 1920×1080 i Mac ga prikazuje ~1:1 u prozoru — **nema TV-upscale
koraka**, pa vidiš 1080p framebuffer oštro (oštrije nego stvarni EON→4K-TV lanac,
gdje TV interpolira 1080p na 4K panel). `960×540` je logički dp prostor uz dpr 2.0,
NE downsampling.

Puno objašnjenje (dp vs px, density tablica, zašto ~960×540, display lanac iza 4K
TV-a, zašto se ne hardkodira): vidi **`docs/android-tv.md` → "Rezolucija, density i
dp"**.

## Gotchas

- **`sdkmanager` "No space left on device" iako SSD ima mjesta:** staging ide na
  `java.io.tmpdir` (interni disk). Forsiraj na kontejner:
  `JAVA_OPTS="-Djava.io.tmpdir=/Volumes/DOMOVINA_ANDROID/tmp" sdkmanager ...`
- **Kontejner nije mountan poslije reboota** → `emulator -list-avds` ne vidi AVD
  (symlink visi). Pokreni `hdiutil attach` (korak 1).
- **Dva uređaja spojena** → `flutter run` traži `-d emulator-5554`; `adb` traži
  `-s emulator-5554`.
- **Prvi Gradle `assembleDebug` je spor** (par minuta, native pluginovi); kasniji
  buildovi su brzi.
