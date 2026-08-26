#!/usr/bin/env node
// Prototip KORAKA "podjela epizode na sponzorske slotove" (plan §3).
// Ne piše nikamo — samo pokazuje kakav bi grid pipeline proizveo iz
// POSTOJEĆIH artefakata (article.json sekcije + summary.json key_topics).
//
//   node scripts/propose-ad-slots.mjs WRE248YCIeI
//   node scripts/propose-ad-slots.mjs WRE248YCIeI --json
//
// Pravila (v0, namjerno konzervativna):
//  1. Granica slota NIKAD ne siječe sekciju — slot je 1..n uzastopnih sekcija.
//  2. Ciljano trajanje slota TARGET_S; broj slotova omeđen [MIN_N, MAX_N].
//  3. Prvih OPENING_S sekundi je zasebna premium zona (ljudi gledaju najviše).
//  4. Kontekst slota = unija keywords + entities njegovih sekcija.

const CDN = 'https://cdn.domovina.ai';
const TARGET_S = 360, MIN_N = 4, MAX_N = 12, OPENING_S = 180;

const ytId = process.argv[2];
const wantJson = process.argv.includes('--json');
if (!ytId) { console.error('Uporaba: node scripts/propose-ad-slots.mjs <youtubeId> [--json]'); process.exit(2); }

const hms = (s) => { const p = String(s).split(':').map(Number); return p.length === 3 ? p[0]*3600+p[1]*60+p[2] : p.length===2 ? p[0]*60+p[1] : p[0]; };
const fmt = (n) => `${String(Math.floor(n/3600)).padStart(2,'0')}:${String(Math.floor(n%3600/60)).padStart(2,'0')}:${String(Math.floor(n%60)).padStart(2,'0')}`;

const main = async () => {
  const [art, sum] = await Promise.all([
    fetch(`${CDN}/data/${ytId}/article.json`).then(r => r.ok ? r.json() : null),
    fetch(`${CDN}/data/${ytId}/summary.json`).then(r => r.ok ? r.json() : null),
  ]);
  if (!art?.iterations) { console.error(`Nema article.json za ${ytId}.`); process.exit(1); }

  const duration = sum?.source?.duration_seconds ?? hms(art.iterations.at(-1).end_time);
  const secs = art.iterations.flatMap((it) => (it.sections || []).map((s) => ({ ...s, iter: it.iteration_number })));
  // Sekcija dobiva [start, end): start = vlastito sidro, end = sidro sljedeće.
  const anchored = secs.map((s, i) => ({
    start: hms(s.screenshot_timestamp),
    end: i + 1 < secs.length ? hms(secs[i + 1].screenshot_timestamp) : duration,
    subtitle: s.subtitle, keywords: s.keywords || [], entities: s.entities || [], iter: s.iter,
  })).filter((s) => s.end > s.start);

  const targetN = Math.max(MIN_N, Math.min(MAX_N, Math.round(duration / TARGET_S)));
  const perSlot = duration / targetN;

  const slots = [];
  let cur = null;
  for (const s of anchored) {
    const isOpening = s.start < OPENING_S;
    if (!cur) { cur = { sections: [s], opening: isOpening }; continue; }
    const wouldEnd = s.end - cur.sections[0].start;
    // Otvaranje se zatvori čim izađemo iz OPENING_S prozora.
    if (cur.opening && !isOpening) { slots.push(cur); cur = { sections: [s], opening: false }; continue; }
    if (!cur.opening && wouldEnd > perSlot * 1.35 && slots.length + 1 < targetN) {
      slots.push(cur); cur = { sections: [s], opening: false };
    } else cur.sections.push(s);
  }
  if (cur) slots.push(cur);

  const out = slots.map((sl, i) => {
    const start = sl.sections[0].start, end = sl.sections.at(-1).end;
    const kw = [...new Set(sl.sections.flatMap((s) => s.keywords))];
    const ent = [...new Set(sl.sections.flatMap((s) => s.entities))];
    return {
      slotKey: `t:${start}`, index: i, start, end, durationSec: end - start,
      zone: sl.opening ? 'otvaranje' : (i === slots.length - 1 ? 'zatvaranje' : 'tijelo'),
      sections: sl.sections.length,
      naslov: sl.sections[0].subtitle,
      keywords: kw.slice(0, 10), entities: ent.slice(0, 10),
      kwCount: kw.length, entCount: ent.length,
    };
  });

  if (wantJson) { console.log(JSON.stringify({ ytId, duration, targetN, slots: out }, null, 2)); return; }

  console.log(`${ytId} · ${sum?.summary?.title_hr?.slice(0, 70) ?? ''}`);
  console.log(`trajanje ${fmt(duration)} · ${anchored.length} sekcija → ${out.length} slotova (cilj ${targetN})\n`);
  for (const s of out) {
    console.log(`[${String(s.index).padStart(2)}] ${fmt(s.start)}–${fmt(s.end)}  ${String(Math.round(s.durationSec/60)+'min').padEnd(6)} ${s.zone.padEnd(11)} ${s.sections} sek · ${s.kwCount} kw · ${s.entCount} ent`);
    console.log(`     ${s.naslov?.slice(0, 84)}`);
    console.log(`     kw: ${s.keywords.slice(0, 6).join(' · ')}`);
  }
  const d = out.map((s) => s.durationSec);
  console.log(`\nTrajanje slota: min ${Math.round(Math.min(...d)/60)}min · max ${Math.round(Math.max(...d)/60)}min`);
};

main().catch((e) => { console.error(e); process.exit(1); });
