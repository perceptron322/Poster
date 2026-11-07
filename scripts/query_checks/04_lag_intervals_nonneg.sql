DO $$
BEGIN
  IF EXISTS (
      SELECT 1 FROM (
          SELECT o.created_at - LAG(o.created_at) OVER (PARTITION BY o.user_id ORDER BY o.created_at) AS gap
          FROM orders o WHERE o.status = 'paid'
      ) s WHERE gap IS NOT NULL AND gap < INTERVAL '0'
  ) THEN
      RAISE EXCEPTION 'Провал 04: обнаружен отрицательный интервал между заказами (запрос 06)';
  END IF;
  RAISE NOTICE '✅ 04: интервалы LAG (запрос 06) неотрицательны';
END $$;