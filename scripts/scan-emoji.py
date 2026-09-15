#!/usr/bin/env python3
"""Inventura emojija/piktografa u izvoru — reproducira brojke iz
`docs/2026-09-15-emoji-u-sucelju.md` §1.

    python3 scripts/scan-emoji.py            # popis pogodaka
    python3 scripts/scan-emoji.py --summary  # samo brojke

Za razliku od `test/no_emoji_in_strings_test.dart` (koji je tripwire i gleda
SAMO ono što korisnik vidi), ovaj skener gleda sve — uključujući komentare —
jer je njegov posao pokazati razmjer, ne obarati build.
"""
import re
import sys
import pathlib
import subprocess
import unicodedata

PAT = re.compile(
    "[\U0001F000-\U0001FAFF"  # emoji blokovi
    "←-⇿"           # strelice
    "⌀-⏿"           # misc technical (⌚⏱⚙)
    "①-⓿"           # enclosed alphanumerics
    "■-➿"           # geometric + misc symbols + dingbats
    "⬀-⯿"           # misc symbols & arrows
    "️⃣"            # VS16, combining keycap
    "\U0001F1E6-\U0001F1FF"   # regional indicators (zastave)
    "]"
)

ROOTS = ["lib", "web", "assets", "android", "ios", "macos", "test", "scripts"]
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".webp", ".ico", ".ttf", ".otf",
               ".woff", ".woff2", ".mp3", ".mp4", ".zip", ".jar", ".keystore"}


def tracked():
    """Samo datoteke koje git prati.

    Bez ovog filtra sken broji i `ios/Pods/` (RevenueCat SDK ima emojije u
    vlastitom sourceu) pa brojka naraste za ~40 i više ne govori ništa o NAŠEM
    kodu. Izmjereno 15.9.2026.: 925 s Podsima, 884 bez njih.
    """
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", *ROOTS],
        capture_output=True, text=True, check=True,
    ).stdout
    return {pathlib.Path(x) for x in out.split("\0") if x}


def scan():
    for p in sorted(tracked()):
        if not p.is_file() or p.suffix.lower() in SKIP_SUFFIX:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for m in PAT.finditer(line):
                ch = m.group()
                try:
                    name = unicodedata.name(ch)
                except ValueError:
                    name = "?"
                yield str(p), i, ch, name, line.strip()[:150]


def main():
    hits = list(scan())
    summary_only = "--summary" in sys.argv
    if not summary_only:
        for path, line_no, ch, name, line in hits:
            print(f"{path}:{line_no}\t{ch}\tU+{ord(ch):04X} {name}\t{line}")
        print()
    arrows = sum(1 for h in hits if "ARROW" in h[3])
    print(f"ukupno:   {len(hits)}")
    print(f"datoteka: {len({h[0] for h in hits})}")
    print(f"strelice: {arrows}")
    print(f"ostatak:  {len(hits) - arrows}")


if __name__ == "__main__":
    main()
