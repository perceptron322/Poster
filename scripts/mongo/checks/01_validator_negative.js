// Валидатор $jsonSchema и уникальный индекс должны отклонять некорректные документы.
// Ожидаем отказ; если вставка вдруг прошла — проверка падает, мусор удаляется в finally.
const expectReject = (label, fn, codes = [121]) => {
  try { fn(); } catch (e) {
    if (codes.includes(e.code)) { print(`  отклонено: ${label} (code ${e.code})`); return; }
    throw e;
  }
  throw new Error(`НЕ отклонено: ${label}`);
};
const TMP_ID = 900000;
const base = db.event_pages.findOne({ 'event.type': 'concert' });
const fresh = (patch) => ({ ...base, _id: TMP_ID, ...patch });
const marker = new Date('1970-01-02T00:00:00Z');   // created_at мусорных отзывов для очистки

try {
  expectReject('рейтинг отзыва 6', () => db.reviews.insertOne({
    event_id: base._id, user_id: 1, rating: 6, created_at: marker,
  }));
  expectReject('второй отзыв того же пользователя на событие', () => {
    const r = db.reviews.findOne();
    db.reviews.insertOne({ event_id: r.event_id, user_id: r.user_id, rating: 3, created_at: marker });
  }, [11000]);
  expectReject('фестиваль без stages', () => db.event_pages.insertOne(fresh({
    event: { ...base.event, type: 'festival' }, details: {},
  })));
  expectReject('у концерта поле лекции (details.level)', () => db.event_pages.insertOne(fresh({
    details: { ...base.details, level: 'beginner' },
  })));
  expectReject('неизвестный тип события', () => db.event_pages.insertOne(fresh({
    event: { ...base.event, type: 'standup' },
  })));
  expectReject('программа длиннее 50 пунктов', () => db.event_pages.insertOne(fresh({
    program: Array.from({ length: 51 }, (_, i) => ({ starts_at: new Date(), title: `p${i}` })),
  })));
  expectReject('дубликат исполнителя в performer_ids', () => db.event_pages.insertOne(fresh({
    performer_ids: ['perf-0001', 'perf-0001'],
  })));
  expectReject('деньги в снимке события (ticket_price принадлежит PG)', () => db.event_pages.insertOne(fresh({
    event: { ...base.event, ticket_price: 100 },
  })));
  expectReject('исполнитель без kind', () => db.performers.insertOne({
    _id: 'perf-9999', name: 'X', updated_at: new Date(),
  }));
} finally {
  db.event_pages.deleteOne({ _id: TMP_ID });
  db.performers.deleteOne({ _id: 'perf-9999' });
  db.reviews.deleteMany({ created_at: marker });
}
