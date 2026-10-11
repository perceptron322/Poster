-- ============================================================
-- Сравнение планов: сколько партиций затронул запрос, время, буферы.
-- Каждый запрос выполняется один раз для прогрева, затем EXPLAIN ANALYZE.
-- ============================================================
CREATE FUNCTION pg_temp.plan_info(q TEXT)
RETURNS TABLE (scanned INT, plan_ms NUMERIC, exec_ms NUMERIC, buffers BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
    j JSONB;
BEGIN
    EXECUTE q;   -- прогрев
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || q INTO j;
    -- Число разных таблиц/партиций, которые реально читались
    scanned := (SELECT count(DISTINCT r)
                FROM jsonb_path_query(j, 'strict $.**."Relation Name"') r);
    plan_ms := round((j -> 0 ->> 'Planning Time')::NUMERIC, 3);
    exec_ms := round((j -> 0 ->> 'Execution Time')::NUMERIC, 3);
    buffers := (j -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::BIGINT
             + (j -> 0 -> 'Plan' ->> 'Shared Read Blocks')::BIGINT;
    RETURN NEXT;
END $$;

WITH params AS (
    -- Фиксированные значения: покупатель, заказ из середины, день из середины окна
    SELECT 777 AS uid,
           (SELECT max(order_id) / 2 FROM orders) AS oid,
           (SELECT date_trunc('day', min(created_at)) + INTERVAL '30 days' FROM orders) AS day
),
q(n, name, sql) AS (
    SELECT 1, 'by_user',   format('SELECT * FROM %%I WHERE user_id = %s', uid) FROM params
    UNION ALL
    SELECT 2, 'by_id',     format('SELECT * FROM %%I WHERE order_id = %s', oid) FROM params
    UNION ALL
    SELECT 3, 'by_period', format('SELECT count(*), sum(total_price) FROM %%I '
                                  'WHERE created_at >= %L AND created_at < %L',
                                  day, day + INTERVAL '1 day') FROM params
    UNION ALL
    SELECT 4, 'full_scan', 'SELECT status, count(*), sum(total_price) FROM %I GROUP BY status'
)
SELECT q.name AS "запрос", t AS "таблица",
       p.scanned AS "таблиц прочитано", p.plan_ms AS "план, мс",
       p.exec_ms AS "выполнение, мс", p.buffers AS "буферов"
FROM q
CROSS JOIN unnest(ARRAY['orders_plain', 'orders_range', 'orders_hash']) WITH ORDINALITY AS u(t, tn)
CROSS JOIN LATERAL pg_temp.plan_info(format(q.sql, t)) p
ORDER BY q.n, u.tn;
