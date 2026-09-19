BEGIN;
INSERT INTO events (title, datetime, duration, type, ticket_price,
                    status, user_id, location_id)
VALUES ('Наложение', '2026-10-01 20:00+03', '02:00', 'concert',
        1000.00, 'published', 1, 1);

INSERT INTO location_bookings (location_id, event_id, period)
VALUES (1, currval(pg_get_serial_sequence('events','event_id')),
        tstzrange('2026-10-01 20:00+03', '2026-10-01 22:00+03', '[)'));
ROLLBACK;
