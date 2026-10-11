-- Выручка за случайный день. Выгодно RANGE по created_at.
\set d random(0, :ndays - 1)
SELECT count(*), sum(total_price)
FROM __T__
WHERE created_at >= to_timestamp(:t0 + :d * 86400)
  AND created_at <  to_timestamp(:t0 + (:d + 1) * 86400);
