SELECT
    e.title,
    SUM(t.price) AS выручка
FROM events e
JOIN orders  o ON o.event_id = e.event_id
JOIN tickets t ON t.order_id = o.order_id
WHERE t.status = 'valid'
GROUP BY e.event_id, e.title
ORDER BY выручка DESC;