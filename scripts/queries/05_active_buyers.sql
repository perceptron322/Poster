SELECT
    u.name,
    COUNT(o.order_id) AS заказов
FROM users u
JOIN orders o ON o.user_id = u.user_id
GROUP BY u.user_id, u.name
HAVING COUNT(o.order_id) > 1;