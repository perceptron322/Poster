DO $$
BEGIN
  IF EXISTS (
      WITH daily AS (
          SELECT o.created_at::date AS d, SUM(t.price) AS s
          FROM orders o JOIN tickets t ON t.order_id = o.order_id
          WHERE o.status = 'paid' AND t.status IN ('valid','used')
          GROUP BY 1
      ), cum AS (
          SELECT d, s,
                 SUM(s) OVER (ORDER BY d ROWS UNBOUNDED PRECEDING) AS cum_sum,
                 AVG(s) OVER (ORDER BY d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma7
          FROM daily
      )
      SELECT 1 FROM cum
      WHERE cum_sum < 0
         OR cum_sum > (SELECT SUM(s) FROM daily)
         OR ma7 < (SELECT MIN(s) FROM daily) - 0.01
         OR EXISTS (SELECT 1 FROM cum prev WHERE prev.d < cum.d AND prev.cum_sum > cum.cum_sum)
  ) THEN
      RAISE EXCEPTION 'Провал 05: накопительная выручка (запрос 07) не монотонна или не сходится с общей суммой';
  END IF;
  RAISE NOTICE '✅ 05: накопительный и скользящий агрегаты (запрос 07) корректны';
END $$;