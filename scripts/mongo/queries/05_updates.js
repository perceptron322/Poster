// Q5. Характер обновлений: почему исполнители — ссылка, а программа — встраивание.
// Все изменения откатываются в конце, чтобы проверки оставались воспроизводимыми.
const perf = db.event_pages.aggregate([
  { $unwind: '$performer_ids' }, { $group: { _id: '$performer_ids', n: { $sum: 1 } } },
  { $sort: { n: -1, _id: 1 } }, { $limit: 1 },
]).next();
const original = db.performers.findOne({ _id: perf._id });

// (a) Ссылка: переименование исполнителя — ОДИН документ, сколько бы событий его ни упоминало.
const ra = db.performers.updateOne({ _id: perf._id }, { $set: { name: `${original.name} (ребрендинг)`, updated_at: new Date() } });
print(`(a) rename ${perf._id}: modified=${ra.modifiedCount} документ; при встраивании пришлось бы обновить ${perf.n} event_pages`);

// (b) Встраивание: добавление пункта программы — атомарное изменение одного документа,
//     валидатор следит за границей maxItems=50.
const page = db.event_pages.findOne({ 'event.type': 'concert' }, { _id: 1, program: 1, event: 1 });
const rb = db.event_pages.updateOne(
  { _id: page._id },
  { $push: { program: { starts_at: page.event.ends_at, title: 'Бис' } }, $currentDate: { updated_at: true } },
);
print(`(b) $push program в event_pages ${page._id}: modified=${rb.modifiedCount}, пунктов ${page.program.length} → ${page.program.length + 1}`);

let rejected = false;
try {
  db.event_pages.updateOne({ _id: page._id }, { $push: { program: { $each: Array.from({ length: 60 }, (_, i) => ({ starts_at: new Date(), title: `x${i}` })) } } });
} catch (e) { rejected = e.code === 121; }
print(`(b') попытка раздуть программу до 60+ пунктов отклонена валидатором: ${rejected}`);

// (c) Новый отзыв: вставка в reviews + пересчёт кэша rating в странице.
//     Две записи без общей транзакции (standalone MongoDB) — кэш пересчитывается
//     из источника истины идемпотентно, рассогласование ловит checks/03.
const target = db.event_pages.findOne({ 'event.status': 'finished', 'rating.count': { $gt: 0 } }, { _id: 1, rating: 1 });
const reviewId = new ObjectId();
db.reviews.insertOne({ _id: reviewId, event_id: target._id, user_id: 999999, rating: 5, text: 'demo', helpful_votes: 0, created_at: new Date() });
const recalc = (id) => db.event_pages.updateOne({ _id: id }, [{ $set: { rating: {
  $let: { vars: { rs: db.reviews.aggregate([{ $match: { event_id: id } }, { $group: { _id: null, c: { $sum: 1 }, a: { $avg: '$rating' } } }]).toArray()[0] },
    in: { count: { $toInt: '$$rs.c' }, avg: { $round: ['$$rs.a', 2] } } } } } }]);
recalc(target._id);
print(`(c) отзыв в event ${target._id}: rating ${JSON.stringify(target.rating)} → ${JSON.stringify(db.event_pages.findOne({ _id: target._id }).rating)}`);

// откат
db.performers.replaceOne({ _id: perf._id }, original);
db.event_pages.updateOne({ _id: page._id }, { $set: { program: page.program } });
db.reviews.deleteOne({ _id: reviewId });
recalc(target._id);
print('изменения откачены');
