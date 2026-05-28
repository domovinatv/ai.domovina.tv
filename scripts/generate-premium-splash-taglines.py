#!/usr/bin/env python3
"""
Generate premium DOMOVINA.ai splash slides at 3840×2160 (4K).

Auto-fits the biblical citation using PIL font metrics — picks the largest
font size that fits the citation in the allotted box, with proper word-wrap.

PRODUCTION default: generates ONLY splash_full_1.png (Mt 10,26-27 KS) which
is wired into both the Android native splash (launch_background.xml) and
the Flutter TvBootSplash widget. Other 13 verses are KEPT in the VERSES list
as data — pass --all to regenerate full set (e.g. for design review).

Layout source-of-truth: assets/icons/splash-template.svg (open in browser).
This renderer must reflect any layout changes made to the SVG.

Outputs (production):
  android/app/src/main/res/drawable-nodpi/splash_full_1.png  (Android native)
  assets/splash/splash_full_1.png                            (Flutter asset)

Usage:
  python3 scripts/generate-premium-splash-taglines.py         # only #1
  python3 scripts/generate-premium-splash-taglines.py --all   # all 14
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "assets" / "fonts"
OUT_DIR = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi"
# Flutter asset mirror — used by TvBootSplash widget za continuity s native
# splash-om (vidi lib/screens/tv/widgets/tv_boot_splash.dart).
FLUTTER_ASSETS = ROOT / "assets" / "splash"

FONT_VERSE = str(FONTS / "Lora-Italic.ttf")
FONT_WORD = str(FONTS / "Inter-Bold.ttf")
FONT_BODY = str(FONTS / "Inter-Regular.ttf")

W, H = 3840, 2160

NAVY = (0, 47, 108)
NAVY_DARK = (0, 31, 76)
RED = (255, 31, 31)
RED_SOFT = (255, 107, 107)
WHITE = (255, 255, 255)
WHITE_DIM = (255, 255, 255, 128)

# Citation block bounding box
CITATION_BOX_W = 3200
CITATION_BOX_H = 1100
CITATION_FONT_MAX = 240
CITATION_FONT_MIN = 60
CITATION_FONT_STEP = 10
LINE_HEIGHT_RATIO = 1.3

# Layout anchors (y coordinates)
WORDMARK_Y = 240
ACCENT_LINE_Y = 410
ACCENT_LINE_W = 160
ACCENT_LINE_H = 10
ATTR_GAP = 100  # px below citation block bottom
ATTR_FONT = 60
ATTR_LETTER_SPACING = 16
SEP_LINE_Y = 2030
SEP_LINE_W = 800
SEP_LINE_H = 4
BOTTOM_TAGLINE_Y_FROM_BOTTOM = 80
BOTTOM_TAGLINE_FONT = 44


# Verse pool. #1 is the long Mt 10,26-28 passage (default native splash).
# #2-14 match defaultBibleVerses order in
# lib/screens/tv/widgets/tv_loading_tips.dart so indices align.
#
# Tekst je verbatim iz Jeruzalemske Biblije (Kršćanska sadašnjost,
# https://biblija.ks.hr — službeni hrvatski liturgijski tekst koji se
# čita na misi). Fact-check vs. Magisterium AI snapshot 2026-05-28
# u docs/splash-bible-citations-factcheck.md. Splash konvencija: bez
# `»…«` govornih navodnika, prva slovo veliko, terminal "." umjesto ":".
VERSES: list[tuple[str, str]] = [
    # 1. Mt 10,26-27, native splash default — identičan KS-u (bez retka 28
    # jer cold start na ~2s + Flutter loading ~10s ne ostavlja dovoljno
    # vremena da korisnik pročita sva 3 retka prije HomeScreen-a).
    (
        "Ne bojte ih se dakle. Ta ništa nije skriveno što se neće otkriti "
        "ni tajno što se neće doznati. Što vam govorim u tami, recite na "
        "svjetlu; i što na uho čujete, propovijedajte na krovovima.",
        "Matej 10, 26-27",
    ),
    # 2. Marko 4,22 — KS replacement
    (
        "Ta ništa nije zastrto, osim zato da se očituje; i ništa skriveno, "
        "osim zato da dođe na vidjelo!",
        "Marko 4, 22",
    ),
    # 3. Luka 8,17 — KS replacement
    (
        "Ta ništa nije tajno što se neće očitovati; ništa skriveno što se "
        "neće saznati i na vidjelo doći.",
        "Luka 8, 17",
    ),
    # 4. Luka 12,2 — KS replacement (skriveno, saznati)
    (
        "Ništa nije skriveno što se neće otkriti ni tajno što se neće "
        "saznati.",
        "Luka 12, 2",
    ),
    # 5. Filipljanima 3,20 — KS replacement (Gospodina našega)
    (
        "Naša je pak domovina na nebesima, odakle iščekujemo Spasitelja, "
        "Gospodina našega Isusa Krista.",
        "Filipljanima 3, 20",
    ),
    # 6. Ivan 8,32 — identičan KS-u
    ("Upoznat ćete istinu i istina će vas osloboditi.", "Ivan 8, 32"),
    # 7. Matej 5,37 — KS replacement (typographic single quotes ‘…’,
    # extra comma "Da, da, –")
    (
        "Vaša riječ neka bude: ‘Da, da, – ne, ne!’ "
        "Što je više od toga, od Zloga je.",
        "Matej 5, 37",
    ),
    # 8. Ivan 16,33 — KS replacement (present "imate", ne "ćete imati")
    (
        "U svijetu imate muku, ali hrabri budite – ja sam pobijedio "
        "svijet!",
        "Ivan 16, 33",
    ),
    # 9. Matej 6,21 — KS replacement (dodano "Doista, ")
    ("Doista, gdje ti je blago, ondje će ti biti i srce.", "Matej 6, 21"),
    # 10. Matej 6,33 — KS replacement (bez "Božje")
    (
        "Tražite stoga najprije Kraljevstvo i pravednost njegovu, a sve "
        "će vam se ostalo dodati.",
        "Matej 6, 33",
    ),
    # 11. Ivan 14,6 — identičan KS-u
    (
        "Ja sam Put i Istina i Život: nitko ne dolazi Ocu osim po meni.",
        "Ivan 14, 6",
    ),
    # 12. Matej 22,21 — identičan KS-u
    ("Podajte dakle caru carevo, a Bogu Božje.", "Matej 22, 21"),
    # 13. Matej 9,37 — KS replacement (KRITIČAN fix — drugi prijevod).
    # "radnikâ" sadrži â (U+00E2) — KS oznaka genitiva množine.
    ("Žetve je mnogo, a radnikâ malo.", "Matej 9, 37"),
    # 14. Luka 6,45 — KS replacement (dodano "Ta ")
    ("Ta iz obilja srca usta mu govore.", "Luka 6, 45"),
]


def text_width(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> float:
    return draw.textlength(text, font=font)


def wrap_lines(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    max_width: int,
) -> list[str]:
    """Greedy word-wrap: pack words into lines that fit max_width pixels."""
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if text_width(draw, candidate, font) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def auto_fit_citation(
    draw: ImageDraw.ImageDraw,
    text: str,
    font_path: str,
    max_width: int,
    max_height: int,
) -> tuple[ImageFont.FreeTypeFont, list[str], float]:
    """Find largest font size where wrapped text fits within (max_width, max_height)."""
    for size in range(CITATION_FONT_MAX, CITATION_FONT_MIN - 1, -CITATION_FONT_STEP):
        font = ImageFont.truetype(font_path, size)
        lines = wrap_lines(draw, text, font, max_width)
        line_h = size * LINE_HEIGHT_RATIO
        total_h = len(lines) * line_h
        if total_h <= max_height:
            return font, lines, line_h
    # Last-resort: minimum size, may overflow vertically.
    font = ImageFont.truetype(font_path, CITATION_FONT_MIN)
    lines = wrap_lines(draw, text, font, max_width)
    return font, lines, CITATION_FONT_MIN * LINE_HEIGHT_RATIO


def draw_gradient_bg(img: Image.Image) -> None:
    """Vertical gradient from NAVY (top) to NAVY_DARK (bottom)."""
    draw = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        r = round(NAVY[0] * (1 - t) + NAVY_DARK[0] * t)
        g = round(NAVY[1] * (1 - t) + NAVY_DARK[1] * t)
        b = round(NAVY[2] * (1 - t) + NAVY_DARK[2] * t)
        draw.line([(0, y), (W, y)], fill=(r, g, b))


def draw_letter_spaced(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    x_center: float,
    y: float,
    fill: tuple,
    spacing: int,
) -> None:
    """Render text with manual letter-spacing, horizontally centered at x_center."""
    chars = list(text)
    char_widths = [text_width(draw, c, font) for c in chars]
    total_w = sum(char_widths) + spacing * (len(chars) - 1)
    x = x_center - total_w / 2
    for c, cw in zip(chars, char_widths):
        draw.text((x, y), c, font=font, fill=fill)
        x += cw + spacing


def generate(idx: int, citation: str, attribution: str) -> Path:
    out_path = OUT_DIR / f"splash_full_{idx}.png"

    img = Image.new("RGB", (W, H), NAVY)
    draw_gradient_bg(img)

    draw = ImageDraw.Draw(img, "RGBA")

    # 1. Wordmark
    wm_font = ImageFont.truetype(FONT_WORD, 104)
    wm_text = "DOMOVINA.ai"
    wm_w = text_width(draw, wm_text, wm_font)
    draw.text(((W - wm_w) / 2, WORDMARK_Y), wm_text, font=wm_font, fill=WHITE)

    # 2. Red accent line
    draw.rectangle(
        [
            ((W - ACCENT_LINE_W) / 2, ACCENT_LINE_Y),
            ((W + ACCENT_LINE_W) / 2, ACCENT_LINE_Y + ACCENT_LINE_H),
        ],
        fill=RED,
    )

    # 3. Citation (auto-fit Lora Italic)
    cite_font, cite_lines, line_h = auto_fit_citation(
        draw, citation, FONT_VERSE, CITATION_BOX_W, CITATION_BOX_H
    )
    total_text_h = len(cite_lines) * line_h
    # Center citation block vertically, shifted slightly above geometric center
    # to leave room for attribution below.
    block_start_y = (H - total_text_h) / 2 - 120
    for i, line in enumerate(cite_lines):
        lw = text_width(draw, line, cite_font)
        draw.text(
            ((W - lw) / 2, block_start_y + i * line_h),
            line,
            font=cite_font,
            fill=WHITE,
        )

    # 4. Attribution — em-dash + uppercase, letter-spaced
    attr_text = f"— {attribution.upper()}"
    attr_font = ImageFont.truetype(FONT_WORD, ATTR_FONT)
    attr_y = block_start_y + total_text_h + ATTR_GAP
    draw_letter_spaced(
        draw, attr_text, attr_font, W / 2, attr_y, RED_SOFT, ATTR_LETTER_SPACING
    )

    # 5. Bottom separator + tagline
    draw.rectangle(
        [
            ((W - SEP_LINE_W) / 2, SEP_LINE_Y),
            ((W + SEP_LINE_W) / 2, SEP_LINE_Y + SEP_LINE_H),
        ],
        fill=WHITE_DIM,
    )
    body_font = ImageFont.truetype(FONT_BODY, BOTTOM_TAGLINE_FONT)
    body_text = "AI-obrada katoličkih podcasta"
    body_w = text_width(draw, body_text, body_font)
    draw.text(
        ((W - body_w) / 2, H - BOTTOM_TAGLINE_Y_FROM_BOTTOM - BOTTOM_TAGLINE_FONT),
        body_text,
        font=body_font,
        fill=WHITE_DIM,
    )

    img.save(out_path, optimize=True)
    return out_path


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)
    for f in (FONT_VERSE, FONT_WORD, FONT_BODY):
        if not Path(f).exists():
            raise SystemExit(f"Missing font: {f}")

    # Default: only generate #1 (production). --all = full set for design review.
    generate_all = "--all" in sys.argv
    verses = VERSES if generate_all else VERSES[:1]
    if not generate_all:
        print("Production mode — generating only splash_full_1. "
              "Use --all to regenerate full 14-verse set.")
        print()

    for i, (citation, attribution) in enumerate(verses, start=1):
        # Pre-compute font size for the log line
        img_dummy = Image.new("RGB", (1, 1))
        d_dummy = ImageDraw.Draw(img_dummy)
        font, lines, _ = auto_fit_citation(
            d_dummy, citation, FONT_VERSE, CITATION_BOX_W, CITATION_BOX_H
        )
        print(
            f"[{i:2}/{len(verses)}] font={font.size:3}px  lines={len(lines)}  "
            f"len={len(citation):3}  attr={attribution}"
        )
        out = generate(i, citation, attribution)
        # Mirror to Flutter assets for TvBootSplash continuity.
        shutil.copy2(out, FLUTTER_ASSETS / out.name)

    print()
    print(f"Done. Generated {len(verses)} premium splash slide(s) @ 4K:")
    for p in sorted(OUT_DIR.glob("splash_full_*.png"), key=lambda x: int(x.stem.split("_")[-1])):
        size_kb = p.stat().st_size // 1024
        print(f"  {p.name}  {size_kb}KB")


if __name__ == "__main__":
    main()
