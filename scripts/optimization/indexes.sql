-- Каталог: частичный индекс только по опубликованным мероприятиям, упорядоченный по дате.
-- INCLUDE добавляет в листья индекса все остальные колонки, которые читает запрос,
-- поэтому возможен Index Only Scan без обращения к таблице.
CREATE INDEX IF NOT EXISTS idx_bench_published_datetime
    ON events (datetime)
    INCLUDE (title, ticket_price, location_id, user_id)
    WHERE status = 'published';

-- Выручка: частичный индекс по order_id только для действительных билетов, с ценой в листьях.
CREATE INDEX IF NOT EXISTS idx_bench_valid_tickets
    ON tickets (order_id)
    INCLUDE (price)
    WHERE status = 'valid';

VACUUM ANALYZE events;
VACUUM ANALYZE tickets;
