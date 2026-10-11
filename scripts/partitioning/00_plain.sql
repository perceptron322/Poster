-- ============================================================
-- Базовая линия: обычная (непартицированная) копия orders.
-- Структура и индексы те же, что у orders_range / orders_hash,
-- чтобы сравнение было честным.
-- ============================================================
DROP TABLE IF EXISTS orders_plain;
DROP SEQUENCE IF EXISTS orders_plain_order_id_seq;

CREATE SEQUENCE orders_plain_order_id_seq AS INTEGER;

CREATE TABLE orders_plain (
    order_id    INTEGER NOT NULL DEFAULT nextval('orders_plain_order_id_seq'),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    status      VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'cancelled', 'refunded')),
    total_price DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (total_price >= 0),
    user_id     INT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    event_id    INT NOT NULL REFERENCES events(event_id) ON DELETE RESTRICT,
    PRIMARY KEY (order_id)
);

INSERT INTO orders_plain (order_id, created_at, status, total_price, user_id, event_id)
SELECT order_id, created_at, status, total_price, user_id, event_id FROM orders;

CREATE INDEX ON orders_plain (user_id);
CREATE INDEX ON orders_plain (event_id);
CREATE INDEX ON orders_plain (created_at);

SELECT setval('orders_plain_order_id_seq', (SELECT max(order_id) FROM orders_plain));
VACUUM ANALYZE orders_plain;
