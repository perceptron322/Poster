-- ============================================================
-- Тестовые данные. Прогонять ПОСЛЕ make migrate.
-- ============================================================
BEGIN;

-- ---------- users ----------
INSERT INTO users (user_id, name, email, role)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'Алиса Организатор', 'alice@example.com', 'organizer'),
  (2, 'Борис Покупатель',  'boris@example.com', 'customer'),
  (3, 'Вера Покупатель',   'vera@example.com',  'customer');

-- ---------- locations ----------
INSERT INTO locations (location_id, name, address, capacity)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'КЗ «Октябрь»',    'Москва, Ленина 1',  100),
  (2, 'Лекторий «Наука»', 'СПб, Невский 10',   50);

-- ---------- events ----------
INSERT INTO events (event_id, title, description, cover, datetime, duration,
                    type, ticket_price, status, user_id, location_id)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'Концерт «Осень»', 'Живая музыка', 'http://img/1.jpg',
      '2026-10-01 19:00+03', '02:00', 'concert', 1500.00, 'published', 1, 1),
  (2, 'Лекция по Go',    'Про горутины', 'http://img/2.jpg',
      '2026-11-05 13:00+03', '01:30', 'lecture',  500.00, 'published', 1, 2);

-- ---------- location_bookings ----------
INSERT INTO location_bookings (location_id, event_id, period) VALUES
  (1, 1, tstzrange('2026-10-01 19:00+03', '2026-10-01 21:00+03', '[)')),
  (2, 2, tstzrange('2026-11-05 13:00+03', '2026-11-05 14:30+03', '[)'));

-- Синхронизируем sequence, чтобы IDENTITY не конфликтовал с ручными id
SELECT setval(pg_get_serial_sequence('users','user_id'),     (SELECT MAX(user_id)     FROM users));
SELECT setval(pg_get_serial_sequence('locations','location_id'), (SELECT MAX(location_id) FROM locations));
SELECT setval(pg_get_serial_sequence('events','event_id'),   (SELECT MAX(event_id)    FROM events));

COMMIT;