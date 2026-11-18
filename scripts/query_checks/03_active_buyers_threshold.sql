DO $$
BEGIN
  IF EXISTS (
      WITH uoc AS (
          SELECT user_id, COUNT(*) AS cnt, SUM(total_price) AS spent
          FROM orders WHERE status = 'paid' GROUP BY user_id
      )
      SELECT 1 FROM uoc WHERE cnt <= 1 OR spent < 0
  ) THEN
      RAISE EXCEPTION 'Провал 03: в результате запроса 05 есть покупатели с cnt <= 1 или отрицательной суммой';
  END IF;
  RAISE NOTICE '✅ 03: активные покупатели (запрос 05) проходят порог и неотрицательность';
END $$;