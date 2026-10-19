-- Сводка о состоянии БД для сверки исходной и восстановленной копий.
-- Запускается с psql -At на обеих сторонах, результаты сравниваются diff'ом.
-- Если исходная БД изменилась после бэкапа, сверка покажет расхождение.

-- Данные: число строк и md5 содержимого каждой таблицы.
SELECT format(
    'SELECT %L, %L, count(*), md5(coalesce(string_agg(t::text, %L ORDER BY t::text), %L)) FROM %I.%I t',
    'table', c.relname, E'\n', '', n.nspname, c.relname)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
ORDER BY c.relname
\gexec

-- Схема: ограничения, индексы, расширения, текущие значения последовательностей.
-- Для CHECK с IN (...) pg_dump/pg_restore меняет расстановку приведений типов
-- (ARRAY[...]::text[] -> ARRAY[(...)::text, ...]), смысл тот же — сравниваем без них.
SELECT 'constraint', conrelid::regclass, conname,
       regexp_replace(pg_get_constraintdef(oid), '::[a-z ]+(\[\])?|[()]', '', 'g')
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
ORDER BY 2::text, 3;

SELECT 'index', indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY 2;

SELECT 'extension', extname, extversion
FROM pg_extension
ORDER BY 2;

SELECT 'sequence', sequencename, last_value
FROM pg_sequences
WHERE schemaname = 'public'
ORDER BY 2;

-- Безопасность: роли и права на таблицы.
SELECT 'role', rolname, rolsuper, rolcanlogin, rolcreatedb, rolcreaterole, rolreplication
FROM pg_roles
WHERE rolname !~ '^pg_'
ORDER BY 2;

SELECT 'grant', grantee, table_name, string_agg(privilege_type, ',' ORDER BY privilege_type)
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
GROUP BY grantee, table_name
ORDER BY 2, 3;
