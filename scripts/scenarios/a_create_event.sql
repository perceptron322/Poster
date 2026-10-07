BEGIN;

INSERT INTO events (title, description, cover, datetime, duration,
                    type, ticket_price, status, user_id, location_id)
VALUES ('Концерт «Зима»', 'Новогодний', 'http://img/3.jpg',
        '2026-12-01 19:00+03', '02:00', 'concert', 2000.00,
        'published', 1, 1)
RETURNING event_id \gset

INSERT INTO location_bookings (location_id, event_id, start_time, end_time)
VALUES (1, :event_id,
        '2026-12-01 19:00+03',
        '2026-12-01 21:00+03');

COMMIT;