// Кэш event_pages.rating совпадает с агрегатом по reviews (источник истины для рейтинга).
const bad = db.event_pages.aggregate([
  { $lookup: {
      from: 'reviews', localField: '_id', foreignField: 'event_id', as: 'r',
      pipeline: [{ $project: { rating: 1 } }],
  } },
  { $project: { rating: 1, count: { $size: '$r' }, avg: { $round: [{ $avg: '$r.rating' }, 2] } } },
  { $match: { $expr: { $or: [{ $ne: ['$rating.count', '$count'] }, { $ne: ['$rating.avg', '$avg'] }] } } },
]).toArray();
print(`  страниц с рассинхроном rating: ${bad.length}`);
bad.slice(0, 5).forEach((b) => printjson(b));
if (bad.length) throw new Error('rating не совпадает с reviews');
