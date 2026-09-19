BEGIN;
SELECT event_id, user_id, status, datetime
FROM events WHERE event_id = 2 FOR UPDATE;

UPDATE events SET status = 'cancelled'
WHERE event_id = 2 AND user_id = 1
  AND status = 'published' AND datetime > now();

UPDATE tickets SET status = 'cancelled'
WHERE status = 'valid'
  AND order_id IN (SELECT order_id FROM orders WHERE event_id = 2);

UPDATE orders SET status = 'cancelled'
WHERE event_id = 2 AND status IN ('paid', 'pending');

DELETE FROM location_bookings WHERE event_id = 2;
COMMIT;
