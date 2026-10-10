#!/usr/bin/env python3
"""Provjera titlova riječ po riječ u pravom Chromeu — mobitel u portraitu
(traka ISPOD playera) i u landscapeu (overlay preko slike, kao i prije).

    python3 scripts/verify-subtitle-words.py --build build/web
    python3 scripts/verify-subtitle-words.py --build build/web --words /put/do/words.json
    python3 scripts/verify-subtitle-words.py --base https://domovina.ai

`--build` poslužuje lokalni `flutter build web` izlaz preko Playwright
routea (SPA fallback na index.html, COOP/COEP kao `_worker.js`), bez servera.
`--words` podmetne lokalni `words.json` umjesto CDN-ovog — tako se izgled
provjeri prije nego je pipeline išta objavio. Snimke idu u `--out`.

Emulacija iPhonea treba i `navigator.platform` (vidi memoriju
„automation browser slow paint"): Flutter platformu čita odatle, a o njoj
ovisi `subtitlesBelowPlayer`. Treba `pip install playwright` + Google Chrome.
"""
import argparse
import mimetypes
import pathlib
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

LOCAL = 'http://local.test'
UA = ('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1')


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', default=None)
    ap.add_argument('--build', default=None)
    ap.add_argument('--words', default=None)
    ap.add_argument('--video', default='fln3cFCwHcs')
    ap.add_argument('--t', type=int, default=60)
    ap.add_argument('--out', default='/tmp')
    a = ap.parse_args()
    base = LOCAL if a.build else (a.base or 'https://domovina.ai')
    out = pathlib.Path(a.out)

    with sync_playwright() as p:
        b = p.chromium.launch(
            channel='chrome', headless=False,
            args=['--autoplay-policy=no-user-gesture-required'],
        )
        for name, w, h in (('portrait', 390, 844), ('landscape', 844, 390)):
            ctx = b.new_context(
                viewport={'width': w, 'height': h}, device_scale_factor=2,
                is_mobile=True, has_touch=True, user_agent=UA,
            )
            ctx.add_init_script(
                "Object.defineProperty(navigator,'platform',{get:()=>'iPhone'});"
                "localStorage.setItem('subtitles_enabled','true');"
            )
            if a.build:
                root = pathlib.Path(a.build)

                def serve(route, root=root):
                    path = urlparse(route.request.url).path.lstrip('/')
                    f = root / path
                    if not path or not f.is_file():
                        f = root / 'index.html'
                    ctype = ('application/wasm' if f.suffix == '.wasm'
                             else mimetypes.guess_type(f.name)[0]
                             or 'application/octet-stream')
                    route.fulfill(status=200, body=f.read_bytes(), headers={
                        'content-type': ctype,
                        'cross-origin-opener-policy': 'same-origin',
                        'cross-origin-embedder-policy': 'credentialless',
                    })
                ctx.route(f'{LOCAL}/**', serve)
            if a.words:
                body = pathlib.Path(a.words).read_bytes()
                ctx.route(
                    f'https://cdn.domovina.ai/data/{a.video}/words.json*',
                    lambda r: r.fulfill(status=200, body=body, headers={
                        'content-type': 'application/json',
                        'access-control-allow-origin': '*',
                    }),
                )
            pg = ctx.new_page()
            logs: list[str] = []
            pg.on('pageerror', lambda e: logs.append(f'PAGEERROR: {e}'))
            pg.goto(f'{base}/v/{a.video}/t/{a.t}', wait_until='commit')
            pg.wait_for_timeout(25000)
            # Muted autoplay (nema geste) — tap na „Uključi zvuk" nije bitan za
            # titl, ali reprodukcija mora teći da se isticanje pomiče.
            pg.evaluate("() => { const v=[...document.querySelectorAll('video')].pop();"
                        " if (v) { v.muted = true; v.play(); } }")
            for i in range(3):
                pg.wait_for_timeout(1200)
                pg.screenshot(path=str(out / f'subtitle-words-{name}-{i}.png'))
            t = pg.evaluate("() => { const v=[...document.querySelectorAll('video')].pop();"
                            " return v ? [v.currentTime, v.paused] : null; }")
            print(name, 'video', t, logs[-3:])
            ctx.close()
        b.close()


if __name__ == '__main__':
    main()
