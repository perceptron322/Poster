SELECT
    e.title,
    SUM(t.price) AS выручка
FROM events e
JOIN orders  o ON o.event_id = e.event_id
JOIN tickets t ON t.order_id = o.order_id
WHERE t.status = 'valid'
GROUP BY e.event_id, e.title
ORDER BY выручка DESC
LIMIT 10;

-- Бизнес-задача:
--   Найти самые прибыльные мероприятия.
--
-- Параметры:
--   Нет. LIMIT 10 — для читаемости отчёта.
--
-- Что делает:
--   Соединяет 3 таблицы (events, orders, tickets),
--   группирует по мероприятию, суммирует цену активных билетов.
--   Сортирует по убыванию, берёт топ-10.
--
-- Почему WHERE t.status = 'valid':
--   Возвращённые и отменённые билеты выручку не приносят.