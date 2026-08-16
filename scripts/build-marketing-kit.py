#!/usr/bin/env python3
"""Gradi HTML verzije Anitinih dokumenata iz markdown izvora.

    python3 scripts/build-marketing-kit.py            # oba
    python3 scripts/build-marketing-kit.py proizvod   # samo jedan

Izvori su markdown datoteke u docs/ — uređuj SAMO njih, pa pokreni ovo.
Rezultat ide u build/marketing/ (nije u gitu) i objavljuje se kao artifact.
Traži `pip install markdown`.

Dodavanje novog dokumenta = jedan unos u DOCS. Zajednički su CSS, navigacija,
tablice i tipizacija citata; po dokumentu se razlikuju zaglavlje i to koji
blockquote dobiva koju etiketu.
"""
import re, sys, markdown, pathlib, html as htmlmod

REPO = pathlib.Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------- figure ---
# Jedini ukrasi u dokumentima — oba nose informaciju, ne dekoraciju.

TIMELINE = '''
<figure class="timeline">
  <figcaption>Epizoda <em>„Kako otpustiti pritisak savršene mame?"</em> — Rastući s djecom</figcaption>
  <svg viewBox="0 0 720 74" role="img" aria-label="Na 1 sat i 35 minuta dvosatne epizode spominje se Iva Kraljević">
    <line x1="12" y1="46" x2="708" y2="46" class="tl-track"/>
    <g class="tl-ticks">
      <line x1="12" y1="40" x2="12" y2="52"/><line x1="186" y1="42" x2="186" y2="50"/>
      <line x1="360" y1="42" x2="360" y2="50"/><line x1="534" y1="42" x2="534" y2="50"/>
      <line x1="708" y1="40" x2="708" y2="52"/>
    </g>
    <text x="12" y="68" class="tl-lab">0:00</text>
    <text x="360" y="68" class="tl-lab" text-anchor="middle">1:00</text>
    <text x="708" y="68" class="tl-lab" text-anchor="end">2:00</text>
    <g class="tl-hit">
      <line x1="565" y1="24" x2="565" y2="52"/>
      <circle cx="565" cy="46" r="5.5"/>
      <text x="565" y="16" text-anchor="middle">spominju je — 1:35:19</text>
    </g>
  </svg>
  <p class="tl-note">Nitko ne posluša tuđu dvosatnu epizodu da provjeri spominju li ga.</p>
</figure>'''

# Pokrivenost obradom: jedna slika koja odmah pokaže gdje smijemo biti glasni,
# a gdje moramo biti oprezni. Brojke = §9 dokumenta, mjereno 14.–15. 8. 2026.
_COVER_ROWS = [
    ('Članak, transkript i imena govornika', 99.5, '3 160 od 3 175 epizoda', True),
    ('Ocjena usklađenosti', 9.8, '311 epizoda', False),
    ('Engleski prijevod', 1.3, '40 epizoda', False),
]
COVERAGE = '<figure class="bars">\n  <figcaption>Pokrivenost obradom — što stvarno postoji u arhivu</figcaption>\n' + '\n'.join(
    f'''  <div class="bar-row">
    <span class="bar-lab">{lab}</span>
    <span class="bar-track"><span class="bar-fill{'' if strong else ' thin'}" style="width:{max(pct, 0.8)}%"></span></span>
    <span class="bar-num">{str(pct).replace(".", ",")} %</span>
    <span class="bar-note">{note}</span>
  </div>''' for lab, pct, note, strong in _COVER_ROWS
) + '''
  <p class="tl-note">Gotovo sve je obrađeno. Ocjena i engleski su iznimka — i tako se
  o njima govori.</p>
</figure>'''


# ------------------------------------------------------------- dokumenti ---

def _quotes_marketing(inner):
    """(oznaka, klasa) za blockquote u terenskom priručniku."""
    if 'Predmet:' in inner or 'Bok Iva' in inner:
        return 'nacrt poruke', 'draft'
    if 'jedini izvor činjenica' in inner:
        return 'upute za AI', 'ai'
    return None, None


def _quotes_proizvod(inner, section=''):
    """(oznaka, klasa) za blockquote u opisu proizvoda — ovisi o sekciji."""
    if 'AI asistentu' in inner or 'Brojke uzimaj' in inner:
        return 'upute za AI', 'ai'
    if section.startswith('11'):
        return 'što odgovoriti', 'draft'
    if section.startswith('13'):
        return 'gotov prompt', 'ai'
    return None, None


DOCS = {
    'marketing': dict(
        src='docs/marketing/benefiti-i-outreach.md',
        out='anitin-prirucnik.html',
        title='Anitin terenski priručnik',
        eyebrow='DOMOVINA.ai · terenski priručnik',
        h1='Zašto DOMOVINA.ai, i kako to reći ljudima',
        dek='Benefiti za gledatelje i za podcast kreatore, gotove poruke za '
            'javljanje svih 48 kanala, i pitanja koja se postavljaju korisnicima.',
        stamp='Podaci provjereni 15. kolovoza 2026. Svaka brojka izvučena je iz '
              'živog sustava — nijedna nije procijenjena. Ovaj dokument čitaju dvoje: '
              '<strong>Anita</strong> i <strong>AI asistent</strong> koji iz njega '
              'piše objave i mailove.',
        footer='Brojke se mijenjaju kako stižu nove epizode — reci Matiji da osvježi dokument.',
        quotes=_quotes_marketing,
        figures={'<!--TIMELINE-->': TIMELINE},
    ),
    'proizvod': dict(
        src='docs/podcasterium_b2c_product.md',
        out='podcasterium-proizvod.html',
        title='Podcasterium ljudskim jezikom',
        eyebrow='DOMOVINA.ai · opis proizvoda',
        h1='Što je Podcasterium, ljudskim jezikom',
        dek='Što proizvod jest, koji problem rješava, što korisnik zapravo dobije '
            'i gdje su granice koje ne prelazimo.',
        stamp='Peti dokument u nizu — prva tri pisana su za programiranje, ovaj se '
              'čita naglas. Sve činjenice izmjerene 14.–15. kolovoza 2026. '
              '<strong>Prvo pročitaj §2</strong>: Podcasterium i DOMOVINA.ai nisu ista stvar.',
        footer='Predlošci poruka, brojke po kanalu i postupak razgovora s korisnicima '
               'su u terenskom priručniku.',
        quotes=_quotes_proizvod,
        figures={'<!--POKRIVENOST-->': COVERAGE},
    ),
}


# ----------------------------------------------------------------- build ---

def slugify(t):
    t = re.sub(r'<[^>]+>', '', t)
    t = t.lower().replace('š','s').replace('č','c').replace('ć','c').replace('ž','z').replace('đ','d')
    t = re.sub(r'[^a-z0-9]+', '-', t).strip('-')
    return t


def build(key, doc):
    src = REPO / doc['src']
    out = REPO / 'build/marketing' / doc['out']
    out.parent.mkdir(parents=True, exist_ok=True)

    md = src.read_text(encoding='utf-8')

    # H1 i uvodni blok idu u zaglavlje, ne u tijelo.
    lines = md.split('\n')
    assert lines[0].startswith('# '), f'{src} ne počinje H1 naslovom'
    body_md = '\n'.join(lines[1:])
    body_md = body_md.split('---', 1)[1]  # makni uvodni kurziv + prvu crtu

    conv = markdown.Markdown(extensions=['tables', 'sane_lists', 'attr_list', 'md_in_html'])
    body = conv.convert(body_md)

    # 1. id-evi na naslove za navigaciju
    nav = []

    def h2(m):
        text = m.group(1)
        sid = slugify(text)
        plain = re.sub(r'<[^>]+>', '', text)
        num = re.match(r'^(\d+|Prilog A)', plain)
        nav.append((num.group(1) if num else '•', plain, sid))
        return f'<h2 id="{sid}">{text}</h2>'

    body = re.sub(r'<h2>(.*?)</h2>', h2, body, flags=re.S)
    body = re.sub(r'<h3>(.*?)</h3>',
                  lambda m: f'<h3 id="{slugify(m.group(1))}">{m.group(1)}</h3>',
                  body, flags=re.S)

    # 2. tablice u scroll kontejner
    body = body.replace('<table>', '<div class="scroll"><table>').replace('</table>', '</table></div>')

    # 3. tipizacija blockquoteova — klasifikator zna u kojoj je sekciji citat
    classify = doc['quotes']
    takes_section = classify.__code__.co_argcount > 1

    def type_quotes(section_html, section_title):
        def one(m):
            inner = m.group(1)
            tag, cls = classify(inner, section_title) if takes_section else classify(inner)
            if not cls:
                return f'<blockquote>{inner}</blockquote>'
            return (f'<blockquote class="{cls}">'
                    f'<span class="draft-tag">{tag}</span>{inner}</blockquote>')
        return re.sub(r'<blockquote>(.*?)</blockquote>', one, section_html, flags=re.S)

    parts = re.split(r'(?=<h2 id=)', body)
    body = ''.join(
        type_quotes(p, re.sub(r'<[^>]+>', '', re.search(r'<h2[^>]*>(.*?)</h2>', p, re.S).group(1)))
        if p.startswith('<h2 id=') else type_quotes(p, '')
        for p in parts)

    # 4. figure na svojim mjestima
    for marker, figure in doc['figures'].items():
        body = body.replace(marker, figure)

    # 5. navigacija
    navhtml = '\n'.join(
        f'<a href="#{sid}"><span class="nav-n">{n}</span>'
        f'{htmlmod.escape(t.split(" ", 1)[1] if t[0].isdigit() else t)}</a>'
        for n, t, sid in nav)

    html = PAGE.format(css=CSS, title=htmlmod.escape(doc['title']), eyebrow=doc['eyebrow'],
                       h1=doc['h1'], dek=doc['dek'], stamp=doc['stamp'],
                       nav=navhtml, body=body, src=doc['src'], footer=doc['footer'])
    out.write_text(html, encoding='utf-8')
    print(f'{out} — {len(html)//1024} kB, {len(nav)} sekcija u navigaciji')


CSS = '''
:root{
  --paper:#F6F7FA; --card:#FFFFFF; --ink:#111726; --ink-soft:#4A5468;
  --navy:#002F6C; --navy-soft:#33578F; --accent:#C8102E; --accent-soft:#F3DCE0;
  --rule:#D8DDE6; --rule-soft:#E9ECF2; --tint:#EEF1F7; --shadow:0 1px 2px rgba(16,25,45,.06);
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --paper:#0C1017; --card:#141A24; --ink:#E6EAF2; --ink-soft:#A2ADC0;
    --navy:#8FB4E8; --navy-soft:#6E90BE; --accent:#FF8A8A; --accent-soft:#3A2026;
    --rule:#26303F; --rule-soft:#1C242F; --tint:#161D28; --shadow:none;
  }
}
:root[data-theme="dark"]{
  --paper:#0C1017; --card:#141A24; --ink:#E6EAF2; --ink-soft:#A2ADC0;
  --navy:#8FB4E8; --navy-soft:#6E90BE; --accent:#FF8A8A; --accent-soft:#3A2026;
  --rule:#26303F; --rule-soft:#1C242F; --tint:#161D28; --shadow:none;
}

*{box-sizing:border-box}
body{
  margin:0; background:var(--paper); color:var(--ink);
  font-family:'Iowan Old Style','Palatino Linotype',Palatino,Georgia,'Times New Roman',serif;
  font-size:17px; line-height:1.62; -webkit-text-size-adjust:100%;
}
.sans{font-family:ui-sans-serif,system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}

/* ---- zaglavlje ---- */
header.mast{
  background:var(--card); border-bottom:1px solid var(--rule);
  padding:clamp(2.2rem,6vw,3.6rem) 1.25rem clamp(1.6rem,4vw,2.4rem);
}
.wrap{max-width:44rem; margin:0 auto}
.eyebrow{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.7rem; font-weight:650;
  letter-spacing:.14em; text-transform:uppercase; color:var(--accent); margin:0 0 .9rem;
  display:flex; align-items:center; gap:.6rem;
}
.eyebrow::after{content:""; flex:1; height:1px; background:var(--rule)}
h1{
  font-size:clamp(1.9rem,5.4vw,2.9rem); line-height:1.12; margin:0 0 .7rem;
  font-weight:600; letter-spacing:-.015em; text-wrap:balance; color:var(--navy);
}
.dek{margin:0; color:var(--ink-soft); font-size:1.06rem; max-width:34rem}
.stamp{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.78rem; color:var(--ink-soft);
  margin-top:1.4rem; padding-top:.9rem; border-top:1px solid var(--rule-soft);
}

/* ---- navigacija ---- */
nav.toc{
  background:var(--tint); border-bottom:1px solid var(--rule);
  padding:.85rem 1.25rem; position:sticky; top:0; z-index:5;
  backdrop-filter:saturate(1.4) blur(6px);
}
nav.toc .wrap{display:flex; gap:.4rem; overflow-x:auto; scrollbar-width:thin}
nav.toc a{
  flex:0 0 auto; font-family:ui-sans-serif,system-ui,sans-serif; font-size:.78rem;
  color:var(--ink-soft); text-decoration:none; padding:.32rem .62rem; border-radius:3px;
  white-space:nowrap; display:flex; gap:.42rem; align-items:baseline;
}
nav.toc a:hover,nav.toc a:focus-visible{background:var(--card); color:var(--navy)}
.nav-n{font-variant-numeric:tabular-nums; font-weight:650; color:var(--accent); font-size:.72rem}

/* ---- tijelo ---- */
main{padding:0 1.25rem 5rem}
main .wrap > *{max-width:44rem}
h2{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:1.32rem; font-weight:660;
  letter-spacing:-.01em; color:var(--navy); margin:3.4rem 0 .2rem;
  padding-top:1.5rem; border-top:2px solid var(--navy); text-wrap:balance;
}
h2:first-of-type{margin-top:2.2rem}
h3{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:1.02rem; font-weight:650;
  color:var(--ink); margin:2.2rem 0 .3rem; text-wrap:balance;
}
h4{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.82rem; font-weight:650;
  letter-spacing:.06em; text-transform:uppercase; color:var(--ink-soft);
  margin:1.9rem 0 .2rem;
}
p{margin:.95rem 0}
strong{font-weight:660}
a{color:var(--navy); text-decoration-thickness:1px; text-underline-offset:2px}
hr{border:0; height:1px; background:var(--rule-soft); margin:2.6rem 0}
ul,ol{padding-left:1.3rem; margin:.95rem 0}
li{margin:.42rem 0}
code{
  font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.86em;
  background:var(--tint); padding:.1em .38em; border-radius:3px; color:var(--ink-soft);
}
em{color:var(--ink-soft)}

/* ---- citati i nacrti ---- */
blockquote{
  margin:1.3rem 0; padding:.1rem 0 .1rem 1.15rem;
  border-left:2px solid var(--navy-soft); color:var(--ink-soft); font-style:italic;
}
blockquote.draft,blockquote.ai{
  font-style:normal; color:var(--ink); background:var(--card);
  border:1px solid var(--rule); border-left:3px solid var(--accent);
  border-radius:3px; padding:1.5rem 1.25rem 1.1rem; margin:1.6rem 0; box-shadow:var(--shadow);
  font-size:.97rem;
}
blockquote.ai{border-left-color:var(--navy)}
.draft-tag{
  display:block; font-family:ui-sans-serif,system-ui,sans-serif; font-size:.65rem;
  font-weight:650; letter-spacing:.13em; text-transform:uppercase;
  color:var(--accent); margin-bottom:.7rem;
}
blockquote.ai .draft-tag{color:var(--navy)}
blockquote p:first-of-type{margin-top:0}
blockquote p:last-child{margin-bottom:0}

/* ---- tablice ---- */
.scroll{overflow-x:auto; margin:1.5rem 0; border:1px solid var(--rule); border-radius:3px; background:var(--card)}
table{border-collapse:collapse; width:100%; font-size:.87rem;
  font-family:ui-sans-serif,system-ui,sans-serif; font-variant-numeric:tabular-nums}
th{
  text-align:left; font-weight:650; font-size:.7rem; letter-spacing:.08em; text-transform:uppercase;
  color:var(--ink-soft); background:var(--tint); padding:.62rem .8rem; border-bottom:1px solid var(--rule);
  white-space:nowrap;
}
td{padding:.62rem .8rem; border-bottom:1px solid var(--rule-soft); vertical-align:top; line-height:1.45}
tr:last-child td{border-bottom:0}
td code{background:transparent; padding:0; font-size:.8em}

/* ---- vremenska crta ---- */
.timeline{
  margin:2rem 0; padding:1.3rem 1.25rem 1rem; background:var(--card);
  border:1px solid var(--rule); border-radius:3px; box-shadow:var(--shadow);
}
.timeline figcaption{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.75rem; color:var(--ink-soft);
  margin-bottom:.7rem;
}
.timeline svg{width:100%; height:auto; display:block; overflow:visible}
.tl-track{stroke:var(--rule); stroke-width:2}
.tl-ticks line{stroke:var(--rule); stroke-width:1.5}
.tl-lab{font-family:ui-sans-serif,system-ui,sans-serif; font-size:10px; fill:var(--ink-soft)}
.tl-hit line{stroke:var(--accent); stroke-width:2}
.tl-hit circle{fill:var(--accent)}
.tl-hit text{font-family:ui-sans-serif,system-ui,sans-serif; font-size:11px; font-weight:650; fill:var(--accent)}
.tl-note{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.8rem;
  color:var(--ink-soft); margin:.7rem 0 0;
}

/* ---- trake pokrivenosti ---- */
.bars{
  margin:2rem 0; padding:1.3rem 1.25rem 1rem; background:var(--card);
  border:1px solid var(--rule); border-radius:3px; box-shadow:var(--shadow);
}
.bars figcaption{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.75rem; color:var(--ink-soft);
  margin-bottom:1rem;
}
.bar-row{
  display:grid; grid-template-columns:1fr auto; gap:.35rem .8rem;
  align-items:baseline; margin-bottom:1.05rem;
}
.bar-lab{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.85rem; font-weight:600; color:var(--ink);
}
.bar-num{
  font-family:ui-sans-serif,system-ui,sans-serif; font-size:.85rem; font-weight:650;
  font-variant-numeric:tabular-nums; color:var(--navy); text-align:right;
}
.bar-track{
  grid-column:1 / -1; order:3; display:block; height:8px; border-radius:2px;
  background:var(--tint); border:1px solid var(--rule-soft); overflow:hidden;
}
.bar-fill{display:block; height:100%; background:var(--navy)}
.bar-fill.thin{background:var(--accent)}
.bar-note{
  grid-column:1 / -1; order:4; font-family:ui-sans-serif,system-ui,sans-serif;
  font-size:.75rem; color:var(--ink-soft);
}

/* ---- sitno ---- */
:focus-visible{outline:2px solid var(--accent); outline-offset:2px; border-radius:2px}
@media (prefers-reduced-motion:reduce){*{animation:none !important; transition:none !important}}
@media (max-width:560px){
  body{font-size:16px}
  main{padding:0 1rem 4rem}
  header.mast{padding-left:1rem; padding-right:1rem}
  nav.toc{padding-left:1rem; padding-right:1rem}
}
footer{
  border-top:1px solid var(--rule); background:var(--card);
  padding:2rem 1.25rem 3rem; color:var(--ink-soft); font-size:.85rem;
  font-family:ui-sans-serif,system-ui,sans-serif;
}
'''

PAGE = '''<meta charset="utf-8">
<title>{title}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>{css}</style>

<header class="mast">
  <div class="wrap">
    <p class="eyebrow">{eyebrow}</p>
    <h1>{h1}</h1>
    <p class="dek">{dek}</p>
    <p class="stamp">{stamp}</p>
  </div>
</header>

<nav class="toc" aria-label="Sadržaj"><div class="wrap">{nav}</div></nav>

<main><div class="wrap">
{body}
</div></main>

<footer><div class="wrap">
Izvor: <code>{src}</code> u repozitoriju domovina.ai. {footer}
</div></footer>
'''


if __name__ == '__main__':
    keys = sys.argv[1:] or list(DOCS)
    for k in keys:
        if k not in DOCS:
            sys.exit(f'nepoznat dokument: {k} (poznati: {", ".join(DOCS)})')
        build(k, DOCS[k])
