SELECT
    u.name,
    COUNT(o.order_id) AS заказов
FROM users u
JOIN orders o ON o.user_id = u.user_id
GROUP BY u.user_id, u.name
HAVING COUNT(o.order_id) > 1;

-- Бизнес-вопрос:
--   Кто из покупателей сделал больше одного заказа?
--
-- Параметры:
--   Порог в HAVING: > 1.
--
-- Соединения:
--   users + orders (2 таблицы).
--   GROUP BY + COUNT + HAVING — единственный запрос с HAVING
--   в наборе.
