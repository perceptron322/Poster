SELECT
    o.order_id,
    e.title     AS мероприятие,
    o.total_price,
    o.status,
    u.name      AS покупатель
FROM orders o
JOIN events e ON e.event_id = o.event_id
JOIN users  u ON u.user_id  = o.user_id
WHERE o.user_id = 2
ORDER BY o.created_at DESC
LIMIT 20;

-- Бизнес-задача:
--   Показать последние заказы конкретного покупателя.
--
-- Параметры:
--   user_id — id покупателя. В примере 2.
--
-- Что делает:
--   Соединяет 3 таблицы (orders, events, users).
--   Сортирует по дате оформления, показывает 20 последних.