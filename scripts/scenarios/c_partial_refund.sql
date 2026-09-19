BEGIN;

-- 1) Захватываем заказ блокировкой (без GROUP BY — отдельным запросом)
SELECT order_id, status, total_price
FROM orders
WHERE order_id = 1
FOR UPDATE;

-- 2) Статистика по билетам (без FOR UPDATE — просто чтение)
SELECT o.order_id,
       COUNT(t.ticket_id) FILTER (WHERE t.status = 'valid') AS valid_cnt
FROM orders o
JOIN tickets t ON t.order_id = o.order_id
WHERE o.order_id = 1
GROUP BY o.order_id;

-- 3) Мероприятие ещё не началось? (правило 13)
SELECT e.datetime > now() AS can_refund
FROM events e
JOIN orders o ON o.event_id = e.event_id
WHERE o.order_id = 1;

-- 4) Возвращаем один активный билет
UPDATE tickets
SET status = 'returned'
WHERE ticket_id = (
  SELECT ticket_id FROM tickets
  WHERE order_id = 1 AND status = 'valid'
  ORDER BY ticket_id LIMIT 1
)
RETURNING ticket_id;

-- 5) Пересчитываем total_price
UPDATE orders o
SET total_price = COALESCE((
      SELECT SUM(price) FROM tickets
      WHERE order_id = o.order_id AND status = 'valid'
    ), 0)
WHERE o.order_id = 1;

COMMIT;