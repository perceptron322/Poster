SELECT 
    l.name AS location_name,
    lb.booking_id,
    e.title AS event_title,
    lb.start_time,
    lb.end_time,
    LAG(e.title) OVER (PARTITION BY lb.location_id ORDER BY lb.start_time) AS previous_event_title,
    LAG(lb.end_time) OVER (PARTITION BY lb.location_id ORDER BY lb.start_time) AS previous_event_end_time
FROM location_bookings lb
JOIN locations l ON lb.location_id = l.location_id
JOIN events e ON lb.event_id = e.event_id
ORDER BY l.location_id, lb.start_time
LIMIT 10;