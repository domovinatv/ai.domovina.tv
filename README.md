# Domovina.ai

Flutter web app za vizualizaciju AI-obradjenih podcast epizoda s hrvatskih YouTube kanala.

**Produkcija:** https://domovina.ai

## Arhitektura

- **Flutter Web (Skwasm/WASM)** — Material 3, responsive layout (desktop/mobile)
- **CDN:** https://cdn.domovina.ai — svi podaci (JSON, slike, video) loadaju se u runtimeu
- **Cloudflare Pages** — hosting + edge worker za server-side OG tagove
- **Magisterium AI** — teoloska analiza uskladenosti s katolickim naukom

## Struktura

```
lib/
  main.dart                  — routing, tema, update notifikacija
  models/                    — Dart modeli za sve JSON formate
    channel_index.dart       — /channels/index.json
    channel_detail.dart      — /channels/{id}.json
    podcast_info.dart        — info.json (yt-dlp metadata)
    podcast_summary.dart     — summary.json (Gemini sazretak)
    podcast_outline.dart     — outline.json (poglavlja)
    podcast_article.dart     — article.json (clanak po sekcijama)
    magisterium_data.dart    — article.magisterium.json / _batch.json
    speaker_timeline.dart    — diarized.srt (govornici)
  services/
    cdn_config.dart          — CDN URL builder
    data_service.dart        — HTTP fetch + progressive loader
    open_url.dart            — cross-platform URL opener (web/native)
    update_notifier.dart     — Service Worker update detekcija
  screens/
    home_screen.dart         — odabir kanala → video lista → epizoda
    episode_screen.dart      — glavni viewer s video sync
  widgets/
    hero_section.dart        — thumbnail, naslov, statistike
    summary_section.dart     — sazretak, teme, govornici
    chapters_section.dart    — poglavlja s timestampovima
    article_section.dart     — clanak + inline Magisterium enrichment
    magisterium_section.dart — overall score kartica
    magisterium_article_section.dart — standalone teoloska analiza
    magisterium_panel.dart   — tabbed panel (po sekciji / po bloku)
    citation_helpers.dart    — citation bottom sheet + cleanup
    entities_section.dart    — osobe, mjesta, organizacije
    table_of_contents.dart   — sidebar TOC
    video_panel.dart         — video player, seek bar, speaker timeline
web/
  index.html                 — SW update detekcija
  _worker.js                 — Cloudflare Pages Function (OG tagovi)
  _headers                   — cache control (no-cache za index/SW)
```

## Development

```bash
flutter run -d chrome
```

## Build & Deploy

```bash
# Build Skwasm (WASM)
flutter build web --wasm --release

# Deploy na Cloudflare Pages
npx wrangler pages deploy build/web --project-name=domovina-ai

# Purge CDN cache (potreban .env s CLOUDFLARE_PURGE_TOKEN)
source .env && curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_PURGE_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}'
```

## Environment (.env)

Kopiraj `.env.example` u `.env` i popuni:

```
CLOUDFLARE_PURGE_TOKEN=   # API token s Zone > Cache Purge > Purge permisijom
CLOUDFLARE_ZONE_ID=       # Zone ID za domovina.ai
```
