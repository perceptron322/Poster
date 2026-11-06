SELECT 
    e.event_id,
    e.title,
    e.datetime,
    l.name AS location_name,
    l.address,
    u.name AS organizer_name
FROM events e
JOIN locations l ON e.location_id = l.location_id
JOIN users u ON e.user_id = u.user_id
WHERE e.status = 'published' AND e.datetime > NOW()
ORDER BY e.datetime ASC
LIMIT 10;

-- Бизнес-задача:
--   Показать каталог опубликованных предстоящих мероприятий.
--
-- Параметры:
--   Нет. (Можно добавить фильтр по типу, например: AND e.type = 'concert').
--
-- Что делает:
--   1. Соединяет 3 таблицы (events, locations, users) через JOIN.
--   2. Фильтрует только опубликованные события, дата которых больше текущего момента (NOW()).
--   3. Сортирует результат по дате проведения по возрастанию (от ближайших к дальним).
--