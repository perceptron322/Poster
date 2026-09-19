BEGIN;
INSERT INTO events (title, datetime, duration, type, ticket_price,
                    status, user_id, location_id)
VALUES ('Миг', now() + interval '1 day', '00:00', 'lecture',
        100, 'published', 1, 1);
ROLLBACK;
