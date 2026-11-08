// Q2. Лента отзывов события с keyset-пагинацией (1:N через ссылку).
// Отзывы не встроены: их число не ограничено, они пишутся независимо от страницы,
// и читаются порциями — индекс event_feed (event_id, created_at desc, _id desc).
const eventId = db.event_pages.find({}).sort({ 'rating.count': -1 }).limit(1).next()._id;
const PAGE = 5;
const filter = { event_id: eventId };
const page1 = db.reviews.find(filter, { _id: 1, user_id: 1, rating: 1, created_at: 1 })
  .sort({ created_at: -1, _id: -1 }).limit(PAGE).toArray();
const last = page1[page1.length - 1];
const page2 = db.reviews.find({
  ...filter,
  $or: [{ created_at: { $lt: last.created_at } }, { created_at: last.created_at, _id: { $lt: last._id } }],
}, { _id: 0, user_id: 1, rating: 1, created_at: 1 }).sort({ created_at: -1, _id: -1 }).limit(PAGE).toArray();

print(`event_id=${eventId}, всего отзывов: ${db.reviews.countDocuments(filter)}`);
print('-- страница 1'); page1.forEach((x) => printjson({ user_id: x.user_id, rating: x.rating, created_at: x.created_at }));
print('-- страница 2 (после последнего ключа страницы 1)'); page2.forEach((x) => printjson(x));

const plan = db.reviews.find(filter).sort({ created_at: -1, _id: -1 }).limit(PAGE).explain('executionStats');
const stage = JSON.stringify(plan.queryPlanner.winningPlan);
print(`план: ${stage.includes('IXSCAN') ? 'IXSCAN' : 'COLLSCAN'} по ${stage.match(/"indexName":"([^"]+)"/)?.[1]}, ` +
      `docsExamined=${plan.executionStats.totalDocsExamined}, nReturned=${plan.executionStats.nReturned}`);
