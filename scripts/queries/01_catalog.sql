SELECT
    e.title,
    e.datetime,
    e.ticket_price,
    l.name  AS площадка,
    u.name  AS организатор
FROM events e
JOIN locations l ON l.location_id = e.location_id
JOIN users     u ON u.user_id     = e.user_id
WHERE e.status = 'published'
ORDER BY e.datetime;