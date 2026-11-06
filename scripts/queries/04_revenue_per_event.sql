WITH event_revenue AS (
    SELECT 
        e.type,
        e.event_id,
        e.title,
        SUM(t.price) AS total_revenue
    FROM events e
    JOIN orders o ON e.event_id = o.event_id
    JOIN tickets t ON o.order_id = t.order_id
    WHERE t.status IN ('valid', 'used')
    GROUP BY e.type, e.event_id, e.title
)
SELECT 
    type,
    event_id,
    title,
    total_revenue,
    RANK() OVER (PARTITION BY type ORDER BY total_revenue DESC) AS revenue_rank
FROM event_revenue
ORDER BY type, revenue_rank, event_id ASC
LIMIT :limit OFFSET :offset;

-- Бизнес-задача:
--   Ранжировать мероприятия по выручке внутри каждой категории (например, найти самый прибыльный концерт и самую прибыльную лекцию отдельно).
--
-- Параметры:
--   Нет.
--
-- Что делает:
--   1. CTE `event_revenue`: соединяет 3 таблицы, фильтрует валидные билеты и агрегирует (SUM) общую выручку по каждому мероприятию в разрезе типов.
--   2. Основной запрос: использует оконную функцию RANK() OVER (PARTITION BY type ORDER BY total_revenue DESC) для присвоения места (ранга) внутри каждой группы типа мероприятия.
--   3. Сортирует финальный вывод по типу и рангу для удобного чтения.