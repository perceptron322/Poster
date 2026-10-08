BEGIN;

-- 1. Находим оплаченный заказ с активными билетами
SELECT o.order_id, o.status, o.total_price
FROM orders o
WHERE o.status = 'paid'
  AND EXISTS (
      SELECT 1
      FROM tickets t
      WHERE t.order_id = o.order_id
        AND t.status = 'valid'
  )
ORDER BY o.order_id
LIMIT 1
FOR UPDATE;

-- 2. Проверяем количество активных билетов
SELECT o.order_id,
       COUNT(t.ticket_id) AS valid_cnt
FROM orders o
JOIN tickets t ON t.order_id = o.order_id
WHERE o.order_id = (
    SELECT o2.order_id
    FROM orders o2
    WHERE o2.status = 'paid'
      AND EXISTS (
          SELECT 1
          FROM tickets t2
          WHERE t2.order_id = o2.order_id
            AND t2.status = 'valid'
      )
    ORDER BY o2.order_id
    LIMIT 1
)
AND t.status = 'valid'
GROUP BY o.order_id;

-- 3. Проверяем, что мероприятие ещё не началось
SELECT e.datetime > now() AS can_refund
FROM events e
JOIN orders o ON o.event_id = e.event_id
WHERE o.order_id = (
    SELECT o2.order_id
    FROM orders o2
    WHERE o2.status = 'paid'
      AND EXISTS (
          SELECT 1
          FROM tickets t2
          WHERE t2.order_id = o2.order_id
            AND t2.status = 'valid'
      )
    ORDER BY o2.order_id
    LIMIT 1
);

-- 4. Возвращаем один активный билет
UPDATE tickets
SET status = 'returned'
WHERE ticket_id = (
    SELECT t.ticket_id
    FROM tickets t
    JOIN orders o ON o.order_id = t.order_id
    JOIN events e ON e.event_id = o.event_id
    WHERE o.status = 'paid'
      AND t.status = 'valid'
      AND e.datetime > now()
    ORDER BY t.ticket_id
    LIMIT 1
)
RETURNING ticket_id, status;

-- 5. Пересчитываем стоимость заказа
UPDATE orders o
SET total_price = COALESCE((
    SELECT SUM(t.price)
    FROM tickets t
    WHERE t.order_id = o.order_id
      AND t.status = 'valid'
), 0)
WHERE o.order_id = (
    SELECT o2.order_id
    FROM orders o2
    WHERE o2.status = 'paid'
      AND EXISTS (
          SELECT 1
          FROM tickets t2
          WHERE t2.order_id = o2.order_id
            AND t2.status = 'returned'
      )
    ORDER BY o2.order_id
    LIMIT 1
)
RETURNING order_id, total_price;

COMMIT;
