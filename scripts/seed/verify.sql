-- Объёмы
SELECT 'tickets'  t, count(*) FROM tickets
UNION ALL SELECT 'orders',    count(*) FROM orders
UNION ALL SELECT 'events',    count(*) FROM events
UNION ALL SELECT 'users',     count(*) FROM users
UNION ALL SELECT 'locations', count(*) FROM locations
UNION ALL SELECT 'bookings',  count(*) FROM location_bookings
ORDER BY 1;

-- Осиротевшие (все должны быть 0)
SELECT 'orphan_tickets' k, count(*) FROM tickets t
  LEFT JOIN orders o ON o.order_id = t.order_id WHERE o.order_id IS NULL
UNION ALL
SELECT 'orphan_orders', count(*) FROM orders o
  LEFT JOIN events e ON e.event_id = o.event_id WHERE e.event_id IS NULL
UNION ALL
SELECT 'orphan_bookings', count(*) FROM location_bookings b
  LEFT JOIN events e ON e.event_id = b.event_id WHERE e.event_id IS NULL
UNION ALL
SELECT 'orphan_events_user', count(*) FROM events e
  LEFT JOIN users u ON u.user_id = e.user_id WHERE u.user_id IS NULL
UNION ALL
SELECT 'orphan_events_loc', count(*) FROM events e
  LEFT JOIN locations l ON l.location_id = e.location_id WHERE l.location_id IS NULL;

-- Распределения (должны быть с перекосом)
SELECT 'ticket_status' k, status, count(*) FROM tickets GROUP BY status ORDER BY 3 DESC;
SELECT 'order_status',  status, count(*) FROM orders  GROUP BY status ORDER BY 3 DESC;
SELECT 'event_type',    type,   count(*) FROM events  GROUP BY type   ORDER BY 3 DESC;
SELECT 'user_role',     role,   count(*) FROM users   GROUP BY role   ORDER BY 3 DESC;

-- [З3-сгущение] Распределение событий по 4 четвертям окна
SELECT
  width_bucket(
    EXTRACT(EPOCH FROM (datetime - (now() - interval '30 days'))),
    0, 60*24*3600, 4
  ) AS quarter,
  count(*)
FROM events
GROUP BY quarter
ORDER BY quarter;

-- [З3-сгущение] Заказы по «свежести» относительно события
SELECT
  width_bucket(
    EXTRACT(EPOCH FROM (e.datetime - o.created_at)) / 86400,
    0, 30, 3
  ) AS bucket_days_before,
  count(*)
FROM orders o JOIN events e ON e.event_id = o.event_id
GROUP BY bucket_days_before
ORDER BY bucket_days_before;

-- Пересечения броней (должно быть 0)
SELECT count(*) AS overlapping_bookings
FROM location_bookings a
JOIN location_bookings b
  ON a.location_id = b.location_id AND a.booking_id < b.booking_id
WHERE a.start_time < b.end_time AND b.start_time < a.end_time;