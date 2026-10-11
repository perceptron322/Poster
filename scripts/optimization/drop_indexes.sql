DROP INDEX IF EXISTS idx_bench_published_datetime;
DROP INDEX IF EXISTS idx_bench_valid_tickets;
VACUUM ANALYZE events;
VACUUM ANALYZE tickets;
