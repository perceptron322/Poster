// Ссылочная целостность внутри MongoDB: внешних ключей нет, проверяем сами.
const fail = [];
const count = (coll, pipeline) => db[coll].aggregate([...pipeline, { $count: 'n' }]).toArray()[0]?.n ?? 0;
const report = (label, n, key) => { print(`  ${label}: ${n}`); if (n) fail.push(key); };

// M:N event_pages.performer_ids → performers
report('event_pages.performer_ids без исполнителя', count('event_pages', [
  { $unwind: '$performer_ids' },
  { $lookup: { from: 'performers', localField: 'performer_ids', foreignField: '_id', as: 'm' } },
  { $match: { m: { $size: 0 } } },
]), 'performer_ids');

// 1:N reviews.event_id → event_pages
report('reviews.event_id без страницы', count('reviews', [
  { $lookup: { from: 'event_pages', localField: 'event_id', foreignField: '_id', as: 'm' } },
  { $match: { m: { $size: 0 } } },
]), 'reviews.event_id');

// Пункт программы ссылается только на исполнителя этого же события.
report('program.performer_id вне performer_ids события', count('event_pages', [
  { $unwind: '$program' },
  { $match: { 'program.performer_id': { $exists: true } } },
  { $match: { $expr: { $not: { $in: ['$program.performer_id', '$performer_ids'] } } } },
]), 'program.performer_id');

// Сцена в программе фестиваля существует в details.stages.
report('program.stage вне details.stages', count('event_pages', [
  { $match: { 'event.type': 'festival' } },
  { $unwind: '$program' },
  { $match: { $expr: { $not: { $in: ['$program.stage', '$details.stages.name'] } } } },
]), 'program.stage');

// Труппа спектакля — ссылка на performers с kind = troupe.
report('спектакли с несуществующей труппой', count('event_pages', [
  { $match: { 'event.type': 'theatre' } },
  { $lookup: { from: 'performers', localField: 'details.troupe_id', foreignField: '_id', as: 't' } },
  { $match: { $or: [{ t: { $size: 0 } }, { 't.kind': { $ne: 'troupe' } }] } },
]), 'troupe_id');

if (fail.length) throw new Error(`нарушены ссылки: ${fail.join(', ')}`);
