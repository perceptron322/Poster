BEGIN;
SELECT event_id, ticket_price, status
FROM events WHERE event_id = 1 AND status = 'published'
FOR UPDATE;

SELECT l.capacity
       - COALESCE((
           SELECT COUNT(*) FROM tickets t
           JOIN orders o ON o.order_id = t.order_id
           WHERE o.event_id = 1 AND t.status = 'valid'
         ), 0) AS free_seats
FROM events e
JOIN locations l ON l.location_id = e.location_id
WHERE e.event_id = 1;

INSERT INTO orders (status, total_price, user_id, event_id)
VALUES ('paid', 4500.00, 2, 1)
RETURNING order_id;

INSERT INTO tickets (price, status, order_id)
VALUES (1500.00, 'valid', currval(pg_get_serial_sequence('orders','order_id'))),
       (1500.00, 'valid', currval(pg_get_serial_sequence('orders','order_id'))),
       (1500.00, 'valid', currval(pg_get_serial_sequence('orders','order_id')));
COMMIT;
