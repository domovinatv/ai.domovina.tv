# Deck — izvor

`domovina-seed.html` je izvor seed decka. Objavljuje se kao Artifact; da URL
ostane isti, republish ide **na istu putanju** (ili iz druge sesije s `url`
parametrom).

**Živi URL**: https://claude.ai/code/artifact/5b532553-08b3-497e-8e14-f57f9c886dc1

Strategija, priprema po fondu i zabranjene tvrdnje:
[`../vc-pitch-strategija.md`](../vc-pitch-strategija.md).

## Pravila

- **Bez emojija** (brand pravilo iz `pitch-deck` repoa).
- Navy `#002F6C` + zlato `#C8912A` / `#E3AF35`; Fraunces + Inter.
- Nijedna brojka bez izvora. Sve što nije potvrđeno ide na slajd 12, ne van.
- Slajd rizika (**14**) se **ne briše** da deck izgleda jače.
- **Rule (nijedan primjer nije izmišljen)**: slajd 4 crta pravu epizodu iz
  korpusa, s pravim poglavljima i klikabilnom poveznicom. Maketa je najjači
  signal da je deck generiran; provjerljiv primjer je najjači protusignal.
  Novi primjer se vadi iz MCP-a (`get_episode`), ne piše rukom.

## Slike

Artifact je jedna samostalna HTML datoteka — **relativne putanje do slika ne
rade** pri objavi. Screenshotovi se zato ugrađuju kao `data:` URI. Izvori žive u
`shots/` (JPEG, dulja stranica 1160 px, kvaliteta ~74) da se mogu zamijeniti:

```bash
sips -Z 1160 shot.png --out s.png
sips -s format jpeg -s formatOptions 74 s.png --out shots/shot-home.jpg
```

Uzeti su sa **žive produkcije**, ne iz lokalnog builda. Flutter na
`domovina.ai` traži ~30 s do prvog painta u automatiziranom Chromeu — prerani
screenshot je prazna stranica, ne puknuta stranica.

## Layout

Deck mora stati u ekran bez scrolla na **svakoj** projektorskoj rezoluciji od
1024×768 naviše. Provjereno mjerenjem 26.8.2026. na 1024×768, 1152×720,
1280×720, 1366×768, 1440×900, 1600×900 i 1920×1080 — nula prelijevanja.

- **Rule (gustoća se ne piše u px nego u tokenima)**: `--gap`, `--gap-s`,
  `--cellpad`, `--lipad`, `--srcgap` u `:root`, stisnu se na `max-height:880px`
  i `max-height:800px`. Novi razmak na slajdu ide kroz njih; hardkodirani
  `margin-top` preživi na 1080p i pukne na 720p.
- **Rule (ne ugnježđuj grid u grid za natuknice)**: `ul.plain li` je hanging
  indent (`padding-left` + apsolutna `::before`), ne `display:grid`. Prethodna
  grid izvedba je unutar dvostupčanog `ul.plain.split` razriješila `auto 1fr`
  obrnuto — crtica 409 px, tekst 89 px — i napuhala slajd 12 za 797 px.
- **Rule (labela se ne dimenzionira prema onome na što pokazuje)**: vremenska
  os na slajdu 4 nosi samo `00:00` / `1:44:07`, a objašnjenje je `.tcall` pune
  širine. Ranija flex labela proporcionalna svom segmentu dobila je 114 px.
- Snap je `proximity`, ne `mandatory`, a **Dalje** stranicu viši od ekrana
  prelistava kroz nju prije nego prijeđe na sljedeću — inače je donja polovica
  nedostupna iz kontrola.

## Zašto ovo uopće ima orakl

Mjerenja iz prolaza 26.–27.8.2026. — koje su provjere mehaničke, koliko su
slajdova stvarno probile i zašto: [`../../2026-08-26-pitch-deck-orakl.md`](../../2026-08-26-pitch-deck-orakl.md).
Taj dokument je ulaz za `provjeri.sh` pitch vertikale u `claude-tmux-teams`,
koji još nije napisan.

## Otvoreno

Vidi „Sljedeći krug" u [`../vc-pitch-strategija.md`](../vc-pitch-strategija.md).

Nakon svakog republisha **pomakni share pin** — vanjski čitatelji inače ostaju
na staroj verziji.
