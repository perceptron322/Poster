-- Экспорт из PostgreSQL (источник истины) данных, нужных MongoDB-seed.
-- Mongo получает только идентификаторы и поля-снимки событий; деньги,
-- билеты и брони остаются в PostgreSQL и в Mongo не копируются.
--
--   events    — снимок события для event_pages.event (title, type, status, starts_at, ends_at)
--   attendees — (event_id, user_id) покупателей с оплаченным заказом на
--               завершённое мероприятие: только они могут оставить отзыв.
SELECT json_build_object(
  'events', COALESCE((
    SELECT json_agg(json_build_object(
             'event_id',  e.event_id,
             'title',     e.title,
             'type',      e.type,
             'status',    e.status,
             'starts_at', e.datetime,
             'ends_at',   e.datetime + e.duration
           ) ORDER BY e.event_id)
    FROM events e
  ), '[]'::json),
  'attendees', COALESCE((
    SELECT json_agg(json_build_object('event_id', a.event_id, 'user_id', a.user_id)
                    ORDER BY a.event_id, a.user_id)
    FROM (
      SELECT DISTINCT o.event_id, o.user_id
      FROM orders o
      JOIN events e ON e.event_id = o.event_id
      WHERE o.status = 'paid' AND e.status = 'finished'
    ) a
  ), '[]'::json)
);
