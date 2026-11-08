// Q6. Размер документов — третий критерий выбора «встраивать или ссылаться».
// Страница с встроенной программой ограничена валидатором и весит килобайты;
// отзывы, если бы их встроили, росли бы без границы к лимиту 16 МБ.
const stats = (coll) => db[coll].aggregate([
  { $group: { _id: null, docs: { $sum: 1 }, avg: { $avg: { $bsonSize: '$$ROOT' } }, max: { $max: { $bsonSize: '$$ROOT' } } } },
  { $project: { _id: 0, docs: 1, avg_bytes: { $round: ['$avg', 0] }, max_bytes: '$max' } },
]).next();
['event_pages', 'performers', 'reviews'].forEach((c) => print(`${c.padEnd(12)} ${JSON.stringify(stats(c))}`));

const prog = db.event_pages.aggregate([{ $group: { _id: null, max: { $max: { $size: '$program' } }, avg: { $avg: { $size: '$program' } } } }]).next();
print(`program[]: avg=${prog.avg.toFixed(1)}, max=${prog.max} пунктов (граница валидатора 50)`);

const worst = db.reviews.aggregate([
  { $group: { _id: '$event_id', n: { $sum: 1 }, bytes: { $sum: { $bsonSize: '$$ROOT' } } } },
  { $sort: { bytes: -1 } }, { $limit: 1 },
]).next();
const avgReview = worst.bytes / worst.n;
print(`отзывы самого обсуждаемого события ${worst._id}: ${worst.n} шт, ${worst.bytes} байт ` +
      `(${Math.round((worst.bytes / stats('event_pages').avg_bytes) * 100) / 100}× средней страницы)`);
print(`если встроить: лимит 16 МБ ≈ ${Math.floor((16 * 1024 * 1024) / avgReview)} отзывов, но задолго до него ` +
      `каждое чтение страницы тянуло бы все отзывы, а каждый новый отзыв переписывал бы растущий документ`);
