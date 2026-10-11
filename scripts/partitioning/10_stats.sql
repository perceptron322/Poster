-- Размеры таблиц: данные + индексы (для партицированных — сумма по партициям)
SELECT t.name AS "таблица",
       (SELECT count(*) FROM pg_inherits WHERE inhparent = t.name::regclass) AS "партиций",
       pg_size_pretty(sum(pg_table_size(c.oid)))   AS "данные",
       pg_size_pretty(sum(pg_indexes_size(c.oid))) AS "индексы"
FROM (VALUES ('orders_plain'), ('orders_range'), ('orders_hash')) t(name)
JOIN pg_class c
  ON c.oid = t.name::regclass
  OR c.oid IN (SELECT inhrelid FROM pg_inherits WHERE inhparent = t.name::regclass)
GROUP BY t.name
ORDER BY t.name;

-- Распределение строк по партициям
SELECT tableoid::regclass AS "партиция", count(*) AS "строк",
       min(created_at)::date AS "с", max(created_at)::date AS "по"
FROM orders_range GROUP BY 1 ORDER BY 1;

SELECT tableoid::regclass AS "партиция", count(*) AS "строк"
FROM orders_hash GROUP BY 1 ORDER BY 1;
