-- Каталог мероприятий
EXPLAIN (ANALYZE, BUFFERS)
SELECT e.title, e.datetime, e.ticket_price,
       l.name AS venue, u.name AS organizer
FROM events e
JOIN locations l ON l.location_id = e.location_id
JOIN users u ON u.user_id = e.user_id
WHERE e.status = 'published'
ORDER BY e.datetime;
