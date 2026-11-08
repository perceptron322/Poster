// Q1. Страница мероприятия одним запросом (сценарий S5 «Просмотр мероприятия»).
// Встроенное (event-снимок, details, program, rating) приходит вместе с документом;
// исполнители (M:N, ссылка) и последние отзывы (1:N, ссылка) подтягиваются $lookup.
// В PostgreSQL это были бы JOIN events + locations + 3 таблицы контента + отзывы.
const eventId = db.event_pages.findOne({ 'event.type': 'festival', 'event.status': 'finished' }, { _id: 1 })._id;

const page = db.event_pages.aggregate([
  { $match: { _id: eventId } },
  { $lookup: {
      from: 'performers', localField: 'performer_ids', foreignField: '_id', as: 'performers',
      pipeline: [{ $project: { name: 1, kind: 1, photo: 1 } }],
  } },
  { $lookup: {
      from: 'reviews', localField: '_id', foreignField: 'event_id', as: 'latest_reviews',
      pipeline: [{ $sort: { created_at: -1, _id: -1 } }, { $limit: 3 }, { $project: { _id: 0, user_id: 1, rating: 1, text: 1 } }],
  } },
  { $project: { event: 1, details: 1, program: { $slice: ['$program', 4] }, rating: 1, performers: 1, latest_reviews: 1 } },
]).toArray()[0];

printjson(page);
