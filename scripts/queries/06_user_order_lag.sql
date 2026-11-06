SELECT 
    u.name AS user_name,
    o.order_id,
    o.created_at,
    o.total_price,
    LAG(o.created_at) OVER (PARTITION BY o.user_id ORDER BY o.created_at) AS prev_order_date,
    o.created_at - LAG(o.created_at) OVER (PARTITION BY o.user_id ORDER BY o.created_at) AS time_since_last_order
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.status = 'paid'
ORDER BY o.user_id, o.created_at
LIMIT 10;