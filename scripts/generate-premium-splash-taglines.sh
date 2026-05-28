#!/usr/bin/env bash
# Generate 14 premium DOMOVINA.ai splash slides @ 3840×2160 (4K).
#
# Splash #1: Mt 10,26-28 (long, 3-verse passage — default native splash)
# Splash #2-14: 13 short verses (matching lib/screens/tv/widgets/tv_loading_tips.dart
#               defaultBibleVerses list, in same order so indices align).
#
# Editorial layout:
#   - Navy gradient background
#   - Top: DOMOVINA.ai wordmark (Inter Bold) + red accent line
#   - Center: biblical citation (Lora Italic) — font auto-tiered by length
#   - Below citation: attribution (Inter Bold, uppercase, letter-spaced, light red)
#   - Bottom: "AI-obrada katoličkih podcasta" tagline (Inter Regular, dim)
#
# Fonts in assets/fonts/:
#   - Lora-Italic.ttf, Inter-Bold.ttf, Inter-Regular.ttf
#
# Output: android/app/src/main/res/drawable-nodpi/splash_full_{1..14}.png
#
# Usage: bash scripts/generate-premium-splash-taglines.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FONTS="$ROOT/assets/fonts"
OUT="$ROOT/android/app/src/main/res/drawable-nodpi"

FONT_VERSE="$FONTS/Lora-Italic.ttf"
FONT_WORD="$FONTS/Inter-Bold.ttf"
FONT_BODY="$FONTS/Inter-Regular.ttf"

for f in "$FONT_VERSE" "$FONT_WORD" "$FONT_BODY"; do
    [[ -f "$f" ]] || { echo "Missing font: $f" >&2; exit 1; }
done

# 4K UHD landscape — native Android TV.
W=3840
H=2160
NAVY="#002F6C"
NAVY_DARK="#001F4C"
RED="#FF1F1F"
RED_SOFT="#FF6B6B"
WHITE="#FFFFFF"
WHITE_DIM="#FFFFFF80"

mkdir -p "$OUT"

# Verse pool: (citation_text|attribution).
# #1 = Mt 10,26-28 long passage (3 verses) — primarni native splash.
# #2-14 = identican order kao defaultBibleVerses u tv_loading_tips.dart
# da indeksi imaju 1:1 korespondenciju u dokumentaciji.
declare -a VERSES=(
    # 1. Mt 10,26-28 — DUGAČAK, native splash default (replaces old Mt 10,26 short).
    "Ne bojte ih se dakle. Ta ništa nije skriveno što se neće otkriti ni tajno što se neće doznati. Što vam govorim u tami, recite na svjetlu; i što na uho čujete, propovijedajte na krovovima. Ne bojte se onih koji ubijaju tijelo, ali duše ne mogu ubiti.|Matej 10, 26-28"
    # 2. Marko 4,22
    "Jer ništa nije tajno osim da bi se očitovalo; niti je što skrito osim da iziđe na vidjelo.|Marko 4, 22"
    # 3. Luka 8,17
    "Ta ništa nije tajno što se neće očitovati; ništa skriveno što se ne bi doznalo i na vidjelo izišlo.|Luka 8, 17"
    # 4. Luka 12,2
    "Ništa nije prikriveno što se neće otkriti ni tajno što se neće doznati.|Luka 12, 2"
    # 5. Filipljanima 3,20
    "Naša je pak domovina na nebesima, odakle iščekujemo Spasitelja, Gospodina Isusa Krista.|Filipljanima 3, 20"
    # 6. Ivan 8,32
    "Upoznat ćete istinu i istina će vas osloboditi.|Ivan 8, 32"
    # 7. Matej 5,37
    "Vaša riječ neka bude: 'Da, da – ne, ne!' Što je više od toga, od Zloga je.|Matej 5, 37"
    # 8. Ivan 16,33
    "U svijetu ćete imati muku, ali hrabri budite – ja sam pobijedio svijet!|Ivan 16, 33"
    # 9. Matej 6,21
    "Gdje ti je blago, ondje će ti biti i srce.|Matej 6, 21"
    # 10. Matej 6,33
    "Tražite stoga najprije Kraljevstvo Božje i pravednost njegovu, a sve će vam se ostalo dodati.|Matej 6, 33"
    # 11. Ivan 14,6
    "Ja sam Put i Istina i Život: nitko ne dolazi Ocu osim po meni.|Ivan 14, 6"
    # 12. Matej 22,21
    "Podajte dakle caru carevo, a Bogu Božje.|Matej 22, 21"
    # 13. Matej 9,37
    "Žetva je velika, ali radnika malo.|Matej 9, 37"
    # 14. Luka 6,45
    "Iz obilja srca usta mu govore.|Luka 6, 45"
)

# Tier font size by citation length (chars). Empirically tuned so text
# fills the citation area without overflowing or looking sparse.
font_size_for() {
    local clen=$1
    if   [[ $clen -gt 250 ]]; then echo 130
    elif [[ $clen -gt 150 ]]; then echo 170
    elif [[ $clen -gt 80  ]]; then echo 220
    else                           echo 280
    fi
}

box_height_for() {
    local clen=$1
    if   [[ $clen -gt 250 ]]; then echo 1100
    elif [[ $clen -gt 150 ]]; then echo 900
    elif [[ $clen -gt 80  ]]; then echo 700
    else                           echo 500
    fi
}

i=0
for entry in "${VERSES[@]}"; do
    i=$((i+1))
    IFS='|' read -r CITATION ATTR <<< "$entry"

    OUT_FILE="$OUT/splash_full_${i}.png"
    CLEN=${#CITATION}
    CFONT=$(font_size_for "$CLEN")
    CBOX_H=$(box_height_for "$CLEN")
    ATTR_UPPER=$(echo "$ATTR" | tr '[:lower:]' '[:upper:]')

    echo "[$i/14] $OUT_FILE  (len=$CLEN, font=$CFONT, box_h=$CBOX_H)"
    echo "       attr: $ATTR"

    magick -size "${W}x${H}" \
        gradient:"${NAVY}-${NAVY_DARK}" \
        \
        -font "$FONT_WORD" -pointsize 104 -fill "$WHITE" \
        -gravity North -annotate +0+240 "DOMOVINA.ai" \
        \
        -fill "$RED" -draw "rectangle 1840,410 2000,420" \
        \
        \( -size "3200x${CBOX_H}" \
           -background none -fill "$WHITE" \
           -font "$FONT_VERSE" -pointsize "$CFONT" \
           -gravity Center \
           caption:"$CITATION" \
           \( -size 3200x80 xc:none \) -append \
           \( -size 3200x140 \
              -background none -fill "$RED_SOFT" \
              -font "$FONT_WORD" -pointsize 60 -kerning 16 \
              -gravity Center \
              caption:"$ATTR_UPPER" \
           \) -append \
        \) -gravity Center -geometry +0-60 -composite \
        \
        -fill "$WHITE_DIM" -draw "rectangle 1520,2030 2320,2034" \
        \
        -font "$FONT_BODY" -pointsize 44 -fill "$WHITE_DIM" \
        -gravity South -annotate +0+60 "AI-obrada katoličkih podcasta" \
        \
        -define png:compression-level=9 \
        "$OUT_FILE"
done

echo ""
echo "Done. Generated $i premium splash slides @ 4K:"
ls -lh "$OUT"/splash_full_*.png | awk '{print "  " $NF "  " $5}'
