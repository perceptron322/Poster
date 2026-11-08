// Seed документной модели на основе реальных данных PostgreSQL.
// Вход: /tmp/pg_export.json внутри контейнера (результат scripts/mongo/pg_export.sql).
// Детерминирован: одинаковый экспорт из PG → одинаковые документы.
const fs = require('fs');

const exp = JSON.parse(fs.readFileSync('/tmp/pg_export.json', 'utf8'));
if (!exp.events.length) throw new Error('В PostgreSQL нет событий: сначала make seed-gen');

// mulberry32 — маленький детерминированный PRNG
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const r = rng(42);
const pick = (arr) => arr[Math.floor(r() * arr.length)];
const between = (lo, hi) => lo + Math.floor(r() * (hi - lo + 1));
const sample = (arr, n) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a.slice(0, n);
};
const now = new Date('2026-11-01T00:00:00Z');
const pad = (n) => String(n).padStart(4, '0');

// ---------- performers ----------
const GENRES = ['rock', 'jazz', 'electronic', 'classical', 'indie', 'hip-hop', 'folk'];
const TOPICS = ['databases', 'distributed systems', 'product design', 'history of art', 'astronomy', 'economics'];
const plan = [
  ['musician', 60], ['band', 50], ['dj', 20], ['speaker', 60], ['host', 15],
];
const performers = [];
let n = 0;
for (const [kind, count] of plan) {
  for (let i = 0; i < count; i++) {
    n++;
    const id = `perf-${pad(n)}`;
    performers.push({
      _id: id,
      name: `${kind[0].toUpperCase()}${kind.slice(1)} ${pad(n)}`,
      kind,
      bio: `Короткая биография исполнителя ${id}.`,
      genres: kind === 'speaker' ? sample(TOPICS, between(1, 2)) : sample(GENRES, between(1, 3)),
      links: { site: `https://example.org/${id}`, socials: [`https://social.example.org/${id}`] },
      photo: `https://cdn.example.org/performers/${id}.jpg`,
      updated_at: now,
    });
  }
}
const troupes = [];
for (let i = 1; i <= 15; i++) {
  const id = `troupe-${pad(i)}`;
  troupes.push({
    _id: id, name: `Театральная труппа ${i}`, kind: 'troupe',
    bio: `Труппа ${id}.`, genres: ['drama'], updated_at: now,
  });
}
const byKind = (kinds) => performers.filter((p) => kinds.includes(p.kind));
const pools = {
  concert: byKind(['musician', 'band']),
  festival: byKind(['band', 'dj', 'musician']),
  lecture: byKind(['speaker']),
  other: byKind(['host']),
};

// ---------- event_pages ----------
function programFor(ev, start, end, performerIds, stages) {
  const items = [];
  const count = ev.type === 'festival' ? between(6, 15) : between(2, 5);
  const span = end - start;
  for (let i = 0; i < count; i++) {
    const item = {
      starts_at: new Date(start.getTime() + Math.floor((span * i) / count)),
      title: `Часть ${i + 1}`,
    };
    if (performerIds.length && ev.type !== 'theatre') item.performer_id = performerIds[i % performerIds.length];
    if (stages) item.stage = stages[i % stages.length].name;
    items.push(item);
  }
  return items;
}

function detailsFor(type, troupeId) {
  switch (type) {
    case 'concert': return { genre: pick(GENRES), age_limit: pick([0, 6, 12, 16, 18]), setlist_public: r() < 0.5 };
    case 'lecture': return {
      topic: pick(TOPICS), level: pick(['beginner', 'intermediate', 'advanced']),
      materials: Array.from({ length: between(0, 3) }, (_, i) => `https://materials.example.org/${i}.pdf`),
    };
    case 'theatre': return { troupe_id: troupeId, acts: between(1, 3), age_limit: pick([0, 12, 16]) };
    case 'festival': return {
      stages: sample(GENRES, between(2, 4)).map((g, i) => ({ name: `Сцена ${i + 1}`, genre: g })),
    };
    default: return { note: 'Формат мероприятия описан организатором в свободной форме.' };
  }
}

const pages = exp.events.map((ev) => {
  const start = new Date(ev.starts_at);
  const end = new Date(ev.ends_at);
  let performerIds; let troupeId;
  if (ev.type === 'theatre') {
    troupeId = pick(troupes)._id;
    performerIds = [troupeId];
  } else {
    const k = ev.type === 'festival' ? between(4, 10) : ev.type === 'other' ? 1 : between(1, 3);
    performerIds = sample(pools[ev.type], k).map((p) => p._id);
  }
  const details = detailsFor(ev.type, troupeId);
  return {
    _id: ev.event_id,
    event: { title: ev.title, type: ev.type, status: ev.status, starts_at: start, ends_at: end },
    synced_at: now,
    summary: `Описание страницы мероприятия «${ev.title}».`,
    details,
    program: programFor(ev, start, end, performerIds, details.stages),
    performer_ids: performerIds,
    gallery: Array.from({ length: between(1, 6) }, (_, i) => `https://cdn.example.org/events/${ev.event_id}/${i}.jpg`),
    rating: { count: 0, avg: null },
    updated_at: now,
  };
});

// ---------- reviews ----------
// Отзыв оставляет только покупатель с оплаченным заказом на завершённое событие
// (список приходит из PostgreSQL). Пишет примерно каждый пятый.
const endsAt = new Map(pages.map((p) => [p._id, p.event.ends_at]));
const reviews = [];
for (const a of exp.attendees) {
  if (r() >= 0.2) continue;
  const rating = Math.min(5, Math.max(1, Math.round(3.6 + (r() + r() + r() - 1.5) * 2)));
  reviews.push({
    _id: new ObjectId(),
    event_id: a.event_id,
    user_id: a.user_id,
    rating,
    text: rating >= 4 ? 'Отличное мероприятие, рекомендую.' : 'Ожидал большего.',
    helpful_votes: between(0, 25),
    created_at: new Date(endsAt.get(a.event_id).getTime() + between(1, 72 * 60) * 60_000),
  });
}

// ---------- запись ----------
db.event_pages.deleteMany({});
db.performers.deleteMany({});
db.reviews.deleteMany({});
db.performers.insertMany(performers.concat(troupes));
db.event_pages.insertMany(pages);
db.reviews.insertMany(reviews);

// Пересчёт кэша rating из источника истины (reviews) — тот же код, что и после нового отзыва.
db.reviews.aggregate([
  { $group: { _id: '$event_id', count: { $sum: 1 }, avg: { $avg: '$rating' } } },
  { $project: { rating: { count: { $toInt: '$count' }, avg: { $round: ['$avg', 2] } } } },
  { $merge: { into: 'event_pages', on: '_id', whenMatched: 'merge', whenNotMatched: 'discard' } },
]);

print(`performers:  ${db.performers.countDocuments()}`);
print(`event_pages: ${db.event_pages.countDocuments()}`);
print(`reviews:     ${db.reviews.countDocuments()}`);
