SELECT
    u.name,
    COUNT(o.order_id) AS заказов
FROM users u
JOIN orders o ON o.user_id = u.user_id
GROUP BY u.user_id, u.name
HAVING COUNT(o.order_id) > 30
ORDER BY заказов DESC
LIMIT 20;

-- Бизнес-задача:
--   Найти самых активных покупателей.
--
-- Параметры:
--   Порог в HAVING: > 30. 
--
-- Что делает:
--   Соединяет 2 таблицы (users, orders), группирует по пользователю,
--   считает количество заказов.