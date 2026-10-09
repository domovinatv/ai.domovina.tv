#!/usr/bin/env python3
"""Izmjeri koliko JSON-a naslovnica povuče s cdn.domovina.ai.

Reproducira brojke iz docs/2026-10-08-brzina-ucitavanja-naslovnice.md:
index.json + svi channels/data/<id>.json (to je točno ono što
ChannelCache.prefetchAll povuče pri svakom otvaranju naslovnice), sirovo i
komprimirano, raspodjela po poljima, i procjena za slim listing + home.json.

    python3 scripts/measure-home-payload.py

Bez ovisnosti osim stdliba; brotli se koristi ako je instaliran
(`pip install brotli`), inače samo gzip.
"""
import concurrent.futures as cf
import gzip
import json
import urllib.request
from collections import Counter

try:
    import brotli
except ImportError:  # pragma: no cover
    brotli = None

BASE = 'https://cdn.domovina.ai/channels/data'
FLAGS = ['has_transcript', 'has_diarized', 'has_summary', 'has_article',
         'has_magisterium', 'has_translation_en', 'has_summary_en',
         'has_article_en', 'has_magisterium_en']


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'measure-home'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def sizes(raw: bytes):
    out = {'raw': len(raw), 'gzip': len(gzip.compress(raw, 9))}
    if brotli:
        out['br'] = len(brotli.compress(raw, quality=11))
    return out


def compact(obj) -> bytes:
    return json.dumps(obj, ensure_ascii=False, separators=(',', ':')).encode()


def slim_video(v):
    o = {k: v[k] for k in ('id', 'title', 'date', 'duration_seconds',
                           'magisterium_score') if v.get(k) is not None}
    if v.get('title_hr') and v['title_hr'] != v['title']:
        o['title_hr'] = v['title_hr']
    p = v.get('pipeline') or {}
    o['p'] = sum(1 << i for i, f in enumerate(FLAGS) if p.get(f))
    return o


def mb(d):
    return '  '.join(f'{k} {v / 1e6:.3f} MB' for k, v in d.items())


def total(blobs):
    acc = Counter()
    for b in blobs:
        acc.update(sizes(b))
    return dict(acc)


def main():
    index_raw = get(f'{BASE}/index.json')
    index = json.loads(index_raw)
    ids = [c['id'] for c in index['channels']]
    with cf.ThreadPoolExecutor(8) as ex:
        raws = dict(zip(ids, ex.map(lambda i: get(f'{BASE}/{i}.json'), ids)))
    chans = {i: json.loads(b) for i, b in raws.items()}
    videos = [(i, v) for i, c in chans.items() for v in c.get('videos', [])]

    print(f'kanala: {len(ids)}, epizoda u listinzima: {len(videos)}, '
          f'zahtjeva: {len(ids) + 1}')
    print('index.json         ', mb(sizes(index_raw)))
    print('listinzi (kako su) ', mb(total(raws.values())))
    print('listinzi (compact) ', mb(total(compact(c) for c in chans.values())))

    fields = Counter()
    for _, v in videos:
        for k, val in v.items():
            fields[k] += len(compact(val)) + len(k) + 4
    allf = sum(fields.values())
    print('\nudio polja epizode u compact listingu:')
    for k, n in fields.most_common(10):
        print(f'  {k:18} {n / 1e6:6.3f} MB  {100 * n / allf:5.1f} %')

    slim = [compact({**{k: c[k] for k in c if k != 'videos'},
                     'videos': [slim_video(v) for v in c.get('videos', [])]})
            for c in chans.values()]
    print('\nslim listinzi      ', mb(total(slim)))

    corpus = compact([[v['id'], v.get('abstract'), v.get('topics'),
                       [s.get('suggested_name') for s in v.get('speakers', [])
                        if isinstance(s, dict)]] for _, v in videos])
    print('search korpus      ', mb(sizes(corpus)))

    videos.sort(key=lambda x: x[1].get('date') or '', reverse=True)
    hero = [(i, v) for i, v in videos
            if (v.get('pipeline') or {}).get('has_magisterium')
            and (v.get('magisterium_score') or 0) >= 70]
    home = compact({
        'latest': [{'c': i, **slim_video(v)} for i, v in videos[:120]],
        'hero_candidates': [{'c': i, **slim_video(v)} for i, v in hero[:40]],
    })
    print('home.json (120+40) ', '  '.join(
        f'{k} {v / 1e3:.1f} KB' for k, v in sizes(home).items()))


if __name__ == '__main__':
    main()
