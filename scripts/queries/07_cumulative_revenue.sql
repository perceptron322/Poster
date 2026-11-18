WITH daily_revenue AS (
    SELECT 
        o.created_at::date AS order_date,
        SUM(t.price) AS daily_sum
    FROM orders o
    JOIN tickets t ON o.order_id = t.order_id
    WHERE o.status = 'paid' AND t.status IN ('valid', 'used')
    GROUP BY o.created_at::date
)
SELECT 
    order_date,
    daily_sum,
    SUM(daily_sum) OVER (ORDER BY order_date ROWS UNBOUNDED PRECEDING) AS cumulative_revenue
FROM daily_revenue
ORDER BY order_date
LIMIT :limit OFFSET :offset;