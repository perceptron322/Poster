BEGIN;
INSERT INTO events (title, datetime, duration, type, ticket_price,
                    status, user_id, location_id)
VALUES ('Вчерашний', now() - interval '1 day', '01:00', 'concert',
        100, 'published', 1, 1);
ROLLBACK;
