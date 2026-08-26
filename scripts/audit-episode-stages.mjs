#!/usr/bin/env node
// Audit faza obrade — koliko je epizoda zaglavljeno gdje.
//
// Za svaku epizodu bez `has_article` mlađu od N dana (default 30 — populacija
// rail-a „Upravo stiglo") probe-a CDN i klasificira je u fazu koju vidi i
// aplikacija (`lib/models/episode_status.dart`).
//
// Zašto probe a ne `pipeline` zastavice iz listinga: listing nema zastavicu za
// mediju i zapisuje `thumbnail` putanju koju datoteka tek TREBA imati. Vidi
// docs/2026-08-26-episode-processing-status.md §2.
//
// Cache-buster na svakom probe-u je obavezan — CDN cachira 404 četiri sata.
//
//   node scripts/audit-episode-stages.mjs [--days 30] [--json]

const args = process.argv.slice(2);
const days = Number(args[args.indexOf('--days') + 1]) || 30;
const asJson = args.includes('--json');

const CDN = 'https://cdn.domovina.ai';
const cb = () => `cb=${Math.random().toString(36).slice(2)}`;

const head = async (url) => {
  try {
    return (await fetch(url, { method: 'HEAD' })).status;
  } catch {
    return 0;
  }
};

const idx = await (await fetch(`${CDN}/channels/data/index.json?${cb()}`)).json();
const cutoff = new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);

const pending = [];
for (const c of idx.channels) {
  const r = await fetch(`${CDN}/channels/data/${c.id}.json?${cb()}`);
  if (!r.ok) continue;
  const d = await r.json();
  for (const v of d.videos ?? []) {
    if (!v.pipeline?.has_article && (v.date ?? '') >= cutoff) {
      pending.push({ channel: c.id, id: v.id, date: v.date, title: v.title ?? '' });
    }
  }
}

const rows = [];
for (const e of pending) {
  const [info, h264, audio, legacy] = await Promise.all([
    head(`${CDN}/data/${e.id}/info.json?${cb()}`),
    head(`${CDN}/data/${e.id}/video_h264.mp4?${cb()}`),
    head(`${CDN}/data/${e.id}/audio.mp3?${cb()}`),
    head(`${CDN}/data/${e.id}/video.mp4?${cb()}`),
  ]);
  const hasMedia = [h264, audio, legacy].includes(200);
  rows.push({
    ...e,
    stage: info !== 200 ? 'queued' : hasMedia ? 'mediaReady' : 'fetched',
    ageDays: Math.round((Date.now() - Date.parse(e.date)) / 864e5),
  });
}

if (asJson) {
  console.log(JSON.stringify(rows, null, 2));
} else {
  const counts = {};
  for (const r of rows) counts[r.stage] = (counts[r.stage] ?? 0) + 1;
  console.log(`nedovršenih epizoda ≤${days} dana: ${rows.length}`);
  for (const stage of ['queued', 'fetched', 'mediaReady']) {
    const bucket = rows.filter((r) => r.stage === stage);
    if (!bucket.length) continue;
    const oldest = Math.max(...bucket.map((r) => r.ageDays));
    console.log(`\n${stage}: ${bucket.length} (najstarija ${oldest} d)`);
    for (const r of bucket.sort((a, b) => b.ageDays - a.ageDays)) {
      console.log(`  ${r.date}  ${r.id}  ${r.channel.padEnd(28)} ${r.title.slice(0, 46)}`);
    }
  }
}
