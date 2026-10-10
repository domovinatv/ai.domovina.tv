#!/usr/bin/env python3
"""Koliko bi bio `data/<id>/episode.json` (EpisodeBundle v1) za N najnovijih
epizoda s člankom, i koliko zahtjeva ekran epizode danas pošalje.

Reprodukcija brojki iz docs/2026-10-08-brzina-ucitavanja-naslovnice.md §8.
Samo čita s CDN-a. Upotreba: python3 scripts/measure-episode-bundle.py [N]
"""
import brotli, json, sys, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

CDN = "https://cdn.domovina.ai"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 12
INLINE = ["info.json", "summary.json", "outline.json", "article.json",
          "article.magisterium.json"]
# Sve što ekran epizode danas traži (EpisodeData.load) + medija.
ALL = INLINE + [
    "article.magisterium_batch.json", "article.magisterium_full.json",
    "article.magisterium_full_prompt.md", "article.magisterium_full_v2.json",
    "article.magisterium_full_v2_prompt.md", "summary.en.json",
    "article.en.json", "article.magisterium.en.json",
    "article.magisterium_batch.en.json", "article.magisterium_full_v2.en.json",
    "diarized.srt", "words.json"]
MEDIA = ["video_h264.mp4", "audio.mp3", "video.mp4"]


def get(url, method="GET"):
    req = urllib.request.Request(url, method=method,
                                 headers={"User-Agent": "measure/1"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, (r.read() if method == "GET" else b"")
    except urllib.error.HTTPError as e:
        return e.code, b""


def episodes():
    idx = json.loads(get(f"{CDN}/channels/data/index.json")[1])
    out = []
    for ch in idx["channels"]:
        d = json.loads(get(f"{CDN}/channels/data/{ch['id']}.json")[1])
        for v in d.get("videos", []):
            if (v.get("pipeline") or {}).get("has_article") and v.get("date"):
                out.append((v["date"], v["id"]))
    return [i for _, i in sorted(out, reverse=True)[:N]]


def measure(vid):
    files, inline = [], {}
    for name in ALL:
        st, body = get(f"{CDN}/data/{vid}/{name}")
        if st == 200:
            files.append(name)
            if name in INLINE:
                inline[name] = json.loads(body)
    for name in MEDIA:
        if get(f"{CDN}/data/{vid}/{name}", "HEAD")[0] == 200:
            files.append(name)
    bundle = json.dumps({"version": 1, "files": files, "inline": inline},
                        ensure_ascii=False, separators=(",", ":")).encode()
    # Danas: svaka datoteka 1 zahtjev, svaki 404 još jedan (retry s busterom),
    # + HEAD probe medije redom dok jedan ne uspije.
    missing = sum(1 for n in ALL if n not in files)
    probes = next((i + 1 for i, m in enumerate(MEDIA) if m in files), 3)
    today = len(ALL) + missing + probes
    # S bundleom: 1 + datoteke s popisa koje nisu uložene (bez medije).
    after = 1 + sum(1 for n in files if n not in INLINE and n not in MEDIA)
    return vid, len(bundle), len(brotli.compress(bundle)), today, after


with ThreadPoolExecutor(4) as ex:
    rows = list(ex.map(measure, episodes()))
for r in rows:
    print(f"{r[0]}  bundle {r[1]/1024:6.1f} KB raw {r[2]/1024:5.1f} KB br"
          f"  zahtjeva danas {r[3]:2d} → s bundleom {r[4]}")
n = len(rows)
print(f"prosjek ({n}): bundle {sum(r[2] for r in rows)/n/1024:.1f} KB br, "
      f"zahtjeva {sum(r[3] for r in rows)/n:.1f} → {sum(r[4] for r in rows)/n:.1f}")
