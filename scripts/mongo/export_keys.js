// Выгрузка ключей MongoDB для межбазовой сверки (scripts/mongo/cross_check.sh).
print(EJSON.stringify({
  pages: db.event_pages.find({}, { event: 1 }).toArray().map((p) => ({
    event_id: p._id,
    title: p.event.title,
    type: p.event.type,
    status: p.event.status,
    starts_at: p.event.starts_at.toISOString(),
    ends_at: p.event.ends_at.toISOString(),
  })),
  reviews: db.reviews.find({}, { _id: 0, event_id: 1, user_id: 1 }).toArray(),
}, { relaxed: true }));
