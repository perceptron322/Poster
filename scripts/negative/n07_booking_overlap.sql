BEGIN;

INSERT INTO events (title, datetime, duration, type, ticket_price,
                    status, user_id, location_id)
VALUES ('Наложение', '2026-10-01 20:00+03', '02:00', 'concert',
        1000.00, 'published', 1, 1)
RETURNING event_id \gset

-- Первая бронь
INSERT INTO location_bookings (location_id, event_id, start_time, end_time)
VALUES (1, :event_id,
        '2026-10-01 20:00+03',
        '2026-10-01 22:00+03');

-- Вторая бронь на то же мероприятие → падает на UNIQUE(event_id)
INSERT INTO location_bookings (location_id, event_id, start_time, end_time)
VALUES (1, :event_id,
        '2026-10-02 20:00+03',
        '2026-10-02 22:00+03');

ROLLBACK;