SELECT
    e.title,
    COUNT(t.ticket_id) AS билетов_продано
FROM events e
JOIN orders  o ON o.event_id = e.event_id
JOIN tickets t ON t.order_id = o.order_id
GROUP BY e.event_id, e.title
ORDER BY билетов_продано DESC
LIMIT 10;

-- Бизнес-задача:
--   Найти самые популярные мероприятия по числу билетов.
--
-- Параметры:
--   Нет. Порог не задан, LIMIT 10 — для читаемости отчёта.
--
-- Что делает:
--   Соединяет 3 таблицы (events, orders, tickets),
--   группирует по мероприятию, считает COUNT билетов.
--   Сортирует по убыванию, берёт топ-10.