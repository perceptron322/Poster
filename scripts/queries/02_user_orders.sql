SELECT 
    o.order_id,
    o.created_at,
    o.status,
    o.total_price,
    e.title AS event_title,
    e.datetime AS event_datetime
FROM orders o
JOIN events e ON o.event_id = e.event_id
WHERE o.user_id = 2 -- параметр: ID пользователя (для примера взят пользователь 2, у него больше всего заказов)
ORDER BY o.created_at DESC
LIMIT 10;

-- Бизнес-задача:
--   Показать историю заказов конкретного покупателя.
--
-- Параметры:
--   user_id — ID покупателя (в примере используется 2).
--
-- Что делает:
--   1. Соединяет 2 таблицы (orders, events) для получения названия мероприятия.
--   2. Фильтрует заказы по конкретному пользователю.
--   3. Сортирует результат по дате создания заказа по убыванию (сначала самые свежие).