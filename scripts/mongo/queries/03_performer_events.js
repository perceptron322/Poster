// Q3. Обратная сторона M:N: все мероприятия исполнителя (страница артиста).
// performer_ids — массив ссылок, multikey-индекс performer_events (performer_ids, event.starts_at).
const top = db.event_pages.aggregate([
  { $unwind: '$performer_ids' },
  { $group: { _id: '$performer_ids', events: { $sum: 1 } } },
  { $sort: { events: -1, _id: 1 } }, { $limit: 1 },
]).next();
const performer = db.performers.findOne({ _id: top._id }, { name: 1, kind: 1, genres: 1 });
printjson(performer);

const events = db.event_pages.find(
  { performer_ids: top._id },
  { _id: 1, 'event.title': 1, 'event.type': 1, 'event.status': 1, 'event.starts_at': 1 },
).sort({ 'event.starts_at': 1 }).toArray();
print(`мероприятий: ${events.length}`);
events.slice(0, 5).forEach((e) => printjson({ event_id: e._id, ...e.event }));

const plan = db.event_pages.find({ performer_ids: top._id }).sort({ 'event.starts_at': 1 }).explain();
print(`план: ${JSON.stringify(plan.queryPlanner.winningPlan).match(/"indexName":"([^"]+)"/)?.[1] ?? 'COLLSCAN'}`);
