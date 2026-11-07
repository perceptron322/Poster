DO $$
BEGIN
  IF EXISTS (
      WITH er AS (
          SELECT e.type, e.event_id, SUM(t.price) AS rev
          FROM events e
          JOIN orders o ON o.event_id = e.event_id
          JOIN tickets t ON t.order_id = o.order_id
          WHERE t.status IN ('valid','used')
          GROUP BY e.type, e.event_id
      ), ranked AS (
          SELECT type, event_id, RANK() OVER (PARTITION BY type ORDER BY rev DESC) AS r
          FROM er
      )
      SELECT 1 FROM ranked GROUP BY type
      HAVING MIN(r) <> 1 OR COUNT(*) <> COUNT(DISTINCT event_id)
  ) THEN
      RAISE EXCEPTION 'Провал 02: ранги запроса 04 некорректны (нет ранга 1 или дубли событий)';
  END IF;
  RAISE NOTICE '✅ 02: RANK() из запроса 04 корректен в каждой категории';
END $$;