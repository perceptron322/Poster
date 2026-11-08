// Q4. Поиск по полям, которые есть только у своего типа (полиморфные документы).
// Лекции для начинающих по теме и фестивали с электронной сценой — частичные индексы.
const lectures = db.event_pages.find(
  { 'event.type': 'lecture', 'details.topic': 'databases', 'details.level': 'beginner' },
  { _id: 1, 'event.title': 1, details: 1 },
).toArray();
print(`лекции databases/beginner: ${lectures.length}`);
lectures.slice(0, 3).forEach((d) => printjson({ event_id: d._id, title: d.event.title, details: d.details }));

const festivals = db.event_pages.aggregate([
  { $match: { 'event.type': 'festival', 'details.stages.genre': 'electronic' } },
  { $project: { _id: 1, title: '$event.title',
      electronic_stages: { $filter: { input: '$details.stages', cond: { $eq: ['$$this.genre', 'electronic'] } } } } },
  { $limit: 3 },
]).toArray();
print(`фестивали с электронной сценой (первые ${festivals.length}):`);
festivals.forEach((f) => printjson(f));

const p1 = db.event_pages.find({ 'event.type': 'lecture', 'details.topic': 'databases', 'details.level': 'beginner' }).explain();
const p2 = db.event_pages.find({ 'event.type': 'festival', 'details.stages.genre': 'electronic' }).explain();
const idx = (p) => JSON.stringify(p.queryPlanner.winningPlan).match(/"indexName":"([^"]+)"/)?.[1] ?? 'COLLSCAN';
print(`планы: лекции → ${idx(p1)}, фестивали → ${idx(p2)}`);
