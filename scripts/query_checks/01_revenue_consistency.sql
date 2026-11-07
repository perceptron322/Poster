DO $$
BEGIN
  IF EXISTS (
      WITH q03 AS (
          SELECT e.event_id, SUM(t.price) AS rev
          FROM events e
          JOIN orders o ON e.event_id = o.event_id
          JOIN tickets t ON o.order_id = t.order_id
          WHERE t.status IN ('valid','used')
          GROUP BY e.event_id
      )
      SELECT 1 FROM q03
      WHERE rev <> (
          SELECT COALESCE(SUM(t.price),0)
          FROM orders o JOIN tickets t ON t.order_id = o.order_id
          WHERE o.event_id = q03.event_id AND t.status IN ('valid','used')
      )
  ) THEN
      RAISE EXCEPTION 'Провал 01: выручка по событиям (запрос 03) не сходится с прямым подсчётом';
  END IF;
  RAISE NOTICE '✅ 01: выручка запроса 03 сходится с независимым подсчётом';
END $$;