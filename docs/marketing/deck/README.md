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
- Slajd rizika (12) se **ne briše** da deck izgleda jače.

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

## Otvoreno

Vidi „Sljedeći krug" u [`../vc-pitch-strategija.md`](../vc-pitch-strategija.md).

Nakon svakog republisha **pomakni share pin** — vanjski čitatelji inače ostaju
na staroj verziji.
