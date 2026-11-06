WITH user_order_counts AS (
    SELECT 
        user_id, 
        COUNT(order_id) AS order_count,
        SUM(total_price) AS total_spent
    FROM orders
    WHERE status = 'paid'
    GROUP BY user_id
)
SELECT 
    u.user_id,
    u.name,
    u.email,
    uoc.order_count,
    uoc.total_spent
FROM users u
JOIN user_order_counts uoc ON u.user_id = uoc.user_id
WHERE uoc.order_count > 1
ORDER BY uoc.total_spent DESC, u.user_id ASC
LIMIT :limit OFFSET :offset;

-- Бизнес-задача:
--   Найти активных покупателей, оценив их по количеству успешных заказов и общей сумме затрат.
--
-- Параметры:
--   Порог в WHERE: order_count > 1 (можно увеличить, чтобы найти только самых активных, например, > 5).
--
-- Что делает:
--   1. CTE `user_order_counts`: агрегирует данные из таблицы orders (COUNT заказов и SUM потраченных средств) только для оплаченных статусов.
--   2. Основной запрос: соединяет (JOIN) результат CTE с таблицей users для получения имён и email.
--   3. Фильтрует пользователей, у которых более 1 заказа, и сортирует итог по общей сумме затрат по убыванию.