BEGIN;
INSERT INTO events (title, datetime, duration, type, ticket_price,
                    status, user_id, location_id)
VALUES ('Бесплатное', now() + interval '1 day', '01:00', 'lecture',
        0, 'published', 1, 1);
ROLLBACK;
