-- ============================================================
-- Стратегия A: RANGE-партицирование orders по created_at, шаг — неделя.
--
-- PK обязан включать ключ партицирования → (order_id, created_at).
-- Партиции создаются динамически: от недели самого раннего заказа
-- до недели «сейчас + 2 недели» (запас под вставки в нагрузочном тесте).
-- DEFAULT-партиция ловит всё, что не попало в диапазоны.
-- ============================================================
DROP TABLE IF EXISTS orders_range;
DROP SEQUENCE IF EXISTS orders_range_order_id_seq;

CREATE SEQUENCE orders_range_order_id_seq AS INTEGER;

CREATE TABLE orders_range (
    order_id    INTEGER NOT NULL DEFAULT nextval('orders_range_order_id_seq'),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    status      VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'cancelled', 'refunded')),
    total_price DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (total_price >= 0),
    user_id     INT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    event_id    INT NOT NULL REFERENCES events(event_id) ON DELETE RESTRICT,
    PRIMARY KEY (order_id, created_at)
) PARTITION BY RANGE (created_at);

DO $$
DECLARE
    w_start TIMESTAMPTZ := date_trunc('week', (SELECT min(created_at) FROM orders));
    w_last  TIMESTAMPTZ := date_trunc('week', now() + INTERVAL '2 weeks');
BEGIN
    WHILE w_start <= w_last LOOP
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF orders_range FOR VALUES FROM (%L) TO (%L)',
            'orders_range_' || to_char(w_start, 'YYYYMMDD'),
            w_start, w_start + INTERVAL '1 week');
        w_start := w_start + INTERVAL '1 week';
    END LOOP;
END $$;

CREATE TABLE orders_range_default PARTITION OF orders_range DEFAULT;

INSERT INTO orders_range (order_id, created_at, status, total_price, user_id, event_id)
SELECT order_id, created_at, status, total_price, user_id, event_id FROM orders;

-- Индекс на партицированной таблице создаёт по индексу в каждой партиции.
CREATE INDEX ON orders_range (user_id);
CREATE INDEX ON orders_range (event_id);
CREATE INDEX ON orders_range (created_at);

SELECT setval('orders_range_order_id_seq', (SELECT max(order_id) FROM orders_range));
VACUUM ANALYZE orders_range;
