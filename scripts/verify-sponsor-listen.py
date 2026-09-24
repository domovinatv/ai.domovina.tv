#!/usr/bin/env python3
"""Provjera „Poslušaj poruku sponzora" u pravom Chromeu — reproducira mjerenje
iz `docs/2026-09-24-sponzori-u-snimci-frontend.md` §Provjera.

    python3 scripts/verify-sponsor-listen.py                       # produkcija, 1400 px
    python3 scripts/verify-sponsor-listen.py --width 390 --height 844
    python3 scripts/verify-sponsor-listen.py --base http://localhost:8788

Otvori `/v/<id>/t/8?a11y=1`, klikne gumb iz trake u playeru i svake 2 s očita
`<video>.currentTime`. Očekivano za `aue1GuuMsbA`: start ≈ 5963 s, poruka
„završila" u logu na 6008 s, a reprodukcija se NASTAVLJA (paused == false).

Zašto Playwright a ne Claude-in-Chrome: ondje prozor u pozadini ne crta
frameove (rAF pauziran) pa klik i scroll nemaju vidljiv efekt. Headed Chrome
kroz Playwright crta normalno. Treba `pip install playwright` + instaliran
Google Chrome (channel='chrome', bez preuzimanja Chromiuma).
"""
import argparse
import json
import re

from playwright.sync_api import sync_playwright

POS = (
    "() => { const v=[...document.querySelectorAll('video')].pop();"
    " return v ? [Math.round(v.currentTime*10)/10, v.paused] : null; }"
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', default='https://domovina.ai')
    ap.add_argument('--video', default='aue1GuuMsbA')
    ap.add_argument('--button', default='e-Duhovne vježbe',
                    help='ime sponzora iz trake u playeru (regex prefiks)')
    ap.add_argument('--width', type=int, default=1400)
    ap.add_argument('--height', type=int, default=900)
    ap.add_argument('--seconds', type=int, default=56)
    a = ap.parse_args()

    with sync_playwright() as p:
        b = p.chromium.launch(
            channel='chrome', headless=False,
            args=['--autoplay-policy=no-user-gesture-required'],
        )
        pg = b.new_page(viewport={'width': a.width, 'height': a.height})
        logs: list[str] = []
        pg.on('console', lambda m: logs.append(f'{m.type}: {m.text}'))
        pg.on('pageerror', lambda e: logs.append(f'PAGEERROR: {e}'))
        pg.goto(f'{a.base}/v/{a.video}/t/8?a11y=1')
        pg.wait_for_timeout(14000)

        # Traka u playeru: redak sa sponzorom, gumb „Poslušaj · 0:45" ispod.
        # Na < 900 px je player u ladici koja se sama otvori; na desktopu je
        # u desnom stupcu — u oba slučaja vidljiv bez skrolanja.
        btn = pg.get_by_role('button', name=re.compile(r'Poslušaj · '))
        if not btn.count():
            print(json.dumps({'error': 'gumb nije nađen', 'logs': logs[-10:]}))
            b.close()
            return
        bb = btn.first.bounding_box()
        pg.mouse.click(bb['x'] + bb['width'] / 2, bb['y'] + bb['height'] / 2)

        samples = []
        for _ in range(a.seconds // 2):
            pg.wait_for_timeout(2000)
            samples.append(pg.evaluate(POS))
        print(json.dumps({
            'first': samples[0],
            'last': samples[-4:],
            'sponsor_logs': [l for l in logs if 'SponsorsInVideo' in l],
            'errors': [
                l for l in logs
                if (l.startswith('error') or l.startswith('PAGEERROR'))
                and 'cloudflareinsights' not in l
                and 'ERR_FAILED' not in l and 'status of 404' not in l
            ],
        }, ensure_ascii=False, indent=1))
        b.close()


if __name__ == '__main__':
    main()
