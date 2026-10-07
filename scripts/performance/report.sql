SELECT
    query,
    calls,
    ROUND(total_exec_time::numeric, 3) AS total_ms,
    ROUND(mean_exec_time::numeric, 3) AS mean_ms,
    rows,
    shared_blks_hit,
    shared_blks_read
FROM pg_stat_statements
WHERE dbid = (
    SELECT oid
    FROM pg_database
    WHERE datname = current_database()
)
AND query NOT LIKE '%pg_stat_statements_reset%'
ORDER BY total_exec_time DESC
LIMIT 20;