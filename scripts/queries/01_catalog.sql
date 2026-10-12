SELECT
    e.title,
    e.datetime,
    e.ticket_price,
    l.name  AS площадка,
    u.name  AS организатор
FROM events e
JOIN locations l ON l.location_id = e.location_id
JOIN users     u ON u.user_id     = e.user_id
WHERE e.status = 'published'
ORDER BY e.datetime
LIMIT 20;

-- Бизнес-задача:
--   Показать каталог опубликованных мероприятий.
--
-- Параметры:
--   Нет. Можно добавить фильтр по типу: AND e.type = 'concert'.
--
-- Что делает:
--   Соединяет 3 таблицы (events, locations, users).
--   Сортирует по дате, показывает 20 ближайших.
--