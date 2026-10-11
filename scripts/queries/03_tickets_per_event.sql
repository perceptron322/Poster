SELECT
    e.title,
    COUNT(t.ticket_id) AS билетов_продано
FROM events e
JOIN orders  o ON o.event_id = e.event_id
JOIN tickets t ON t.order_id = o.order_id
GROUP BY e.event_id, e.title
ORDER BY билетов_продано DESC;