SELECT
    o.order_id,
    e.title     AS мероприятие,
    o.total_price,
    o.status,
    u.name      AS покупатель
FROM orders o
JOIN events e ON e.event_id = o.event_id
JOIN users  u ON u.user_id  = o.user_id
WHERE o.user_id = 2;