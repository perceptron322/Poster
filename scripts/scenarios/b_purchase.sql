BEGIN;

-- 1) Проверяем, что мероприятие опубликовано
SELECT event_id, ticket_price, status
FROM events
WHERE event_id = 1 AND status = 'published';

-- 2) Свободных мест — просто для информации
SELECT l.capacity - COALESCE((
         SELECT COUNT(*) FROM tickets t
         JOIN orders o ON o.order_id = t.order_id
         WHERE o.event_id = 1 AND t.status = 'valid'
       ), 0) AS free_seats
FROM events e
JOIN locations l ON l.location_id = e.location_id
WHERE e.event_id = 1;

-- 3) Создаём заказ на 3 билета и запоминаем его id
INSERT INTO orders (status, total_price, user_id, event_id)
VALUES ('paid', 4500.00, 2, 1)
RETURNING order_id \gset

-- 4) Три билета, все привязаны к :order_id
INSERT INTO tickets (price, status, order_id) VALUES
    (1500.00, 'valid', :order_id),
    (1500.00, 'valid', :order_id),
    (1500.00, 'valid', :order_id);

COMMIT;