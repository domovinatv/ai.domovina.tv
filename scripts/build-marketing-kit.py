#!/usr/bin/env python3
"""Gradi HTML verziju Anitinog priručnika iz markdown izvora.

    python3 scripts/build-marketing-kit.py

Izvor je docs/marketing/benefiti-i-outreach.md — uređuj SAMO njega, pa pokreni
ovo. Rezultat ide u build/marketing/ (nije u gitu) i objavljuje se kao artifact.
Traži `pip install markdown`.
"""
import re, markdown, pathlib, html as htmlmod

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / 'docs/marketing/benefiti-i-outreach.md'
OUT = REPO / 'build/marketing/anitin-prirucnik.html'
OUT.parent.mkdir(parents=True, exist_ok=True)

md = SRC.read_text(encoding='utf-8')

# H1 i uvodni blok idu u zaglavlje, ne u tijelo.
lines = md.split('\n')
assert lines[0].startswith('# ')
body_md = '\n'.join(lines[1:])
body_md = body_md.split('---', 1)[1]  # makni uvodni kurziv + prvu crtu

conv = markdown.Markdown(extensions=['tables', 'sane_lists', 'attr_list', 'md_in_html'])
body = conv.convert(body_md)

# --- post-obrada -----------------------------------------------------------
# 1. id-evi na naslove za navigaciju
def slugify(t):
    t = re.sub(r'<[^>]+>', '', t)
    t = t.lower().replace('š','s').replace('č','c').replace('ć','c').replace('ž','z').replace('đ','d')
    t = re.sub(r'[^a-z0-9]+', '-', t).strip('-')
    return t

nav = []
def h2(m):
    text = m.group(1)
    sid = slugify(text)
    num = re.match(r'^(\d+|Prilog A)', re.sub(r'<[^>]+>', '', text))
    nav.append((num.group(1) if num else '•', re.sub(r'<[^>]+>', '', text), sid))
    return f'<h2 id="{sid}">{text}</h2>'
body = re.sub(r'<h2>(.*?)</h2>', h2, body, flags=re.S)
body = re.sub(r'<h3>(.*?)</h3>', lambda m: f'<h3 id="{slugify(m.group(1))}">{m.group(1)}</h3>', body, flags=re.S)

# 2. tablice u scroll kontejner
body = body.replace('<table>', '<div class="scroll"><table>').replace('</table>', '</table></div>')

# 3. tipizacija blockquoteova
def type_quote(m):
    inner = m.group(1)
    if 'Predmet:' in inner or 'Bok Iva' in inner:
        return f'<blockquote class="draft"><span class="draft-tag">nacrt poruke</span>{inner}</blockquote>'
    if 'jedini izvor činjenica' in inner:
        return f'<blockquote class="ai"><span class="draft-tag">upute za AI</span>{inner}</blockquote>'
    return f'<blockquote>{inner}</blockquote>'
body = re.sub(r'<blockquote>(.*?)</blockquote>', type_quote, body, flags=re.S)

# 4. vremenska crta (jedini ukras — nosi informaciju)
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
body = body.replace('<!--TIMELINE-->', TIMELINE)

# 5. navigacija
navhtml = '\n'.join(
    f'<a href="#{sid}"><span class="nav-n">{n}</span>{htmlmod.escape(t.split(" ",1)[1] if t[0].isdigit() else t)}</a>'
    for n, t, sid in nav)

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

HTML = f'''<meta charset="utf-8">
<title>Anitin terenski priručnik</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>{CSS}</style>

<header class="mast">
  <div class="wrap">
    <p class="eyebrow">DOMOVINA.ai · terenski priručnik</p>
    <h1>Zašto DOMOVINA.ai, i kako to reći ljudima</h1>
    <p class="dek">Benefiti za gledatelje i za podcast kreatore, gotove poruke za
    javljanje svih 48 kanala, i pitanja koja se postavljaju korisnicima.</p>
    <p class="stamp">Podaci provjereni 15. kolovoza 2026. Svaka brojka izvučena je iz
    živog sustava — nijedna nije procijenjena. Ovaj dokument čitaju dvoje: <strong>Anita</strong>
    i <strong>AI asistent</strong> koji iz njega piše objave i mailove.</p>
  </div>
</header>

<nav class="toc" aria-label="Sadržaj"><div class="wrap">{navhtml}</div></nav>

<main><div class="wrap">
{body}
</div></main>

<footer><div class="wrap">
Izvor: <code>docs/marketing/benefiti-i-outreach.md</code> u repozitoriju domovina.ai.
Brojke se mijenjaju kako stižu nove epizode — reci Matiji da osvježi dokument.
</div></footer>
'''

OUT.write_text(HTML, encoding='utf-8')
print(f'{OUT} — {len(HTML)//1024} kB, {len(nav)} sekcija u navigaciji')
