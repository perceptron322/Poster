BEGIN;
INSERT INTO tickets (price, status, order_id) VALUES (100, 'valid', 99999);
ROLLBACK;
