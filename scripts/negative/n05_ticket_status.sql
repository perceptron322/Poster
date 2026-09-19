BEGIN;
INSERT INTO tickets (price, status, order_id) VALUES (100, 'доступен', 1);
ROLLBACK;
