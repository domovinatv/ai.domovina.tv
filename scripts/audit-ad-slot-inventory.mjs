#!/usr/bin/env node
// Mjeri koliko oglasnog inventara postoji na cdn.domovina.ai ako se slotovi
// izvedu iz POSTOJEĆE semantičke segmentacije (article.json sekcije).
//
// Zašto: plan `docs/plans/2026-08-26-p2p-oglasni-prostor.md` tvrdi brojke o
// broju slotova i njihovom trajanju. Ovo je naredba koja ih reproducira.
//
//   node scripts/audit-ad-slot-inventory.mjs                 # 12 nasumičnih epizoda
//   node scripts/audit-ad-slot-inventory.mjs --channel domovina_tv
//   node scripts/audit-ad-slot-inventory.mjs --sample 40 --json

const CDN = 'https://cdn.domovina.ai';
const args = process.argv.slice(2);
const flag = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const wantJson = args.includes('--json');
const onlyChannel = flag('--channel', null);
const sampleSize = Number(flag('--sample', 12));

const hmsToSec = (s) => {
  if (typeof s !== 'string') return null;
  const p = s.split(':').map(Number);
  if (p.some(Number.isNaN)) return null;
  return p.length === 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p.length === 2 ? p[0] * 60 + p[1] : p[0];
};

const getJson = async (url) => {
  const r = await fetch(url);
  if (!r.ok) return null;
  return r.json();
};

const pct = (arr, p) => {
  if (!arr.length) return null;
  const s = [...arr].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))];
};

const main = async () => {
  const index = await getJson(`${CDN}/channels/data/index.json`);
  const channels = Array.isArray(index) ? index : index.channels;

  const totals = {
    channels: channels.length,
    episodes: channels.reduce((n, c) => n + (c.video_count || 0), 0),
    hours: channels.reduce((n, c) => n + (c.total_duration_seconds || 0), 0) / 3600,
    followers: channels.reduce((n, c) => n + (c.follower_count || 0), 0),
  };

  const pool = onlyChannel ? channels.filter((c) => c.id === onlyChannel) : channels;
  if (!pool.length) { console.error(`Nema kanala "${onlyChannel}".`); process.exit(2); }

  // Deterministički uzorak: svaki k-ti kanal, prva epizoda iz njegovog listinga.
  const picks = [];
  const step = Math.max(1, Math.floor(pool.length / sampleSize));
  for (let i = 0; i < pool.length && picks.length < sampleSize; i += step) picks.push(pool[i]);

  const rows = [];
  for (const ch of picks) {
    const listing = await getJson(`${CDN}/channels/data/${ch.id}.json?v=${Math.floor(Date.now() / 300000)}`);
    const vids = (listing?.videos || []).filter((v) => v.pipeline?.has_article);
    for (const v of vids.slice(0, onlyChannel ? 50 : 1)) {
      const art = await getJson(`${CDN}/data/${v.id}/article.json`);
      if (!art?.iterations) continue;
      const secs = art.iterations.flatMap((it) => it.sections || []);
      const anchors = secs.map((s) => hmsToSec(s.screenshot_timestamp)).filter((n) => n !== null);
      const gaps = anchors.slice(1).map((t, i) => t - anchors[i]).filter((g) => g > 0);
      const kw = secs.reduce((n, s) => n + (s.keywords || []).length, 0);
      const ents = secs.reduce((n, s) => n + (s.entities || []).length, 0);
      rows.push({
        channel: ch.id, id: v.id, durationSec: v.duration_seconds || 0,
        iterations: art.iterations.length, sections: secs.length,
        medianGapSec: pct(gaps, 50), p10GapSec: pct(gaps, 10), p90GapSec: pct(gaps, 90),
        keywords: kw, entities: ents,
      });
    }
  }

  const allGaps = rows.map((r) => r.medianGapSec).filter(Boolean);
  const secPerEp = rows.map((r) => r.sections);
  const summary = {
    platforma: { ...totals, hours: Number(totals.hours.toFixed(0)) },
    uzorak: { epizoda: rows.length, kanala: new Set(rows.map((r) => r.channel)).size },
    sekcijaPoEpizodi: { min: Math.min(...secPerEp), median: pct(secPerEp, 50), max: Math.max(...secPerEp) },
    razmakIzmeduSidara_s: { p10: pct(allGaps, 10), median: pct(allGaps, 50), p90: pct(allGaps, 90) },
    procijenjenInventar: {
      sekcijeUkupno: Math.round((totals.hours * 3600) / (pct(allGaps, 50) || 1)),
      priOsamSlotovaPoEpizodi: totals.episodes * 8,
    },
  };

  if (wantJson) { console.log(JSON.stringify({ summary, rows }, null, 2)); return; }

  console.log(`Platforma: ${totals.channels} kanala · ${totals.episodes} epizoda · ${totals.hours.toFixed(0)} h · ${totals.followers.toLocaleString('hr')} pratitelja (YouTube)`);
  console.log(`Uzorak: ${rows.length} epizoda iz ${summary.uzorak.kanala} kanala\n`);
  console.log('kanal'.padEnd(26) + 'video'.padEnd(14) + 'traj.'.padEnd(9) + 'iter'.padEnd(6) + 'sekc'.padEnd(6) + 'medij.razmak'.padEnd(14) + 'kw'.padEnd(6) + 'ent');
  for (const r of rows) {
    console.log(
      r.channel.slice(0, 25).padEnd(26) + r.id.padEnd(14) +
      `${Math.round(r.durationSec / 60)}min`.padEnd(9) +
      String(r.iterations).padEnd(6) + String(r.sections).padEnd(6) +
      `${r.medianGapSec}s`.padEnd(14) + String(r.keywords).padEnd(6) + String(r.entities));
  }
  console.log(`\nSekcija po epizodi: min ${summary.sekcijaPoEpizodi.min} · medijan ${summary.sekcijaPoEpizodi.median} · max ${summary.sekcijaPoEpizodi.max}`);
  console.log(`Razmak između sidara: p10 ${summary.razmakIzmeduSidara_s.p10}s · medijan ${summary.razmakIzmeduSidara_s.median}s · p90 ${summary.razmakIzmeduSidara_s.p90}s`);
  console.log(`Procjena inventara: ~${summary.procijenjenInventar.sekcijeUkupno.toLocaleString('hr')} sekcija ukupno · ${summary.procijenjenInventar.priOsamSlotovaPoEpizodi.toLocaleString('hr')} slotova pri 8/epizoda`);
};

main().catch((e) => { console.error(e); process.exit(1); });
