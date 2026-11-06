SELECT 
    e.event_id,
    e.title,
    COUNT(t.ticket_id) AS tickets_sold,
    SUM(t.price) AS total_revenue
FROM events e
JOIN orders o ON e.event_id = o.event_id
JOIN tickets t ON o.order_id = t.order_id
WHERE t.status IN ('valid', 'used')
GROUP BY e.event_id, e.title
ORDER BY total_revenue DESC
LIMIT 10;

-- Бизнес-задача:
--   Найти самые популярные и прибыльные мероприятия по числу проданных билетов.
--
-- Параметры:
--   Нет. (При необходимости можно добавить LIMIT 10 для вывода только топа).
--
-- Что делает:
--   1. Соединяет 3 таблицы (events, orders, tickets).
--   2. Фильтрует только действительные и использованные билеты (исключая возвращённые).
--   3. Группирует данные по мероприятию и применяет агрегатные функции: COUNT (число билетов) и SUM (общая выручка).
--   4. Сортирует итоговый отчёт по убыванию общей выручки.