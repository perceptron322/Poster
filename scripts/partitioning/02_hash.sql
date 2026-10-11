-- ============================================================
-- Стратегия B: HASH-партицирование orders по user_id, 8 партиций.
--
-- PK обязан включать ключ партицирования → (order_id, user_id).
-- Строка попадает в партицию hash(user_id) % 8 = remainder.
-- ============================================================
DROP TABLE IF EXISTS orders_hash;
DROP SEQUENCE IF EXISTS orders_hash_order_id_seq;

CREATE SEQUENCE orders_hash_order_id_seq AS INTEGER;

CREATE TABLE orders_hash (
    order_id    INTEGER NOT NULL DEFAULT nextval('orders_hash_order_id_seq'),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    status      VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'cancelled', 'refunded')),
    total_price DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (total_price >= 0),
    user_id     INT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    event_id    INT NOT NULL REFERENCES events(event_id) ON DELETE RESTRICT,
    PRIMARY KEY (order_id, user_id)
) PARTITION BY HASH (user_id);

DO $$
BEGIN
    FOR r IN 0..7 LOOP
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF orders_hash FOR VALUES WITH (MODULUS 8, REMAINDER %s)',
            'orders_hash_p' || r, r);
    END LOOP;
END $$;

INSERT INTO orders_hash (order_id, created_at, status, total_price, user_id, event_id)
SELECT order_id, created_at, status, total_price, user_id, event_id FROM orders;

CREATE INDEX ON orders_hash (user_id);
CREATE INDEX ON orders_hash (event_id);
CREATE INDEX ON orders_hash (created_at);

SELECT setval('orders_hash_order_id_seq', (SELECT max(order_id) FROM orders_hash));
VACUUM ANALYZE orders_hash;
