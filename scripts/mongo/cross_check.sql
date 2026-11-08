-- Межбазовая сверка: PostgreSQL (источник истины) ↔ MongoDB (контент).
-- Вход: /tmp/mongo_keys.json в контейнере db — выгрузка из Mongo (см. cross_check.sh).
-- При любом расхождении DO-блок бросает исключение → make mongo-check падает.
CREATE TEMP TABLE m AS SELECT pg_read_file('/tmp/mongo_keys.json')::jsonb AS j;

CREATE TEMP TABLE m_pages AS
SELECT (p->>'event_id')::int AS event_id, p->>'title' AS title, p->>'type' AS type,
       p->>'status' AS status, (p->>'starts_at')::timestamptz AS starts_at,
       (p->>'ends_at')::timestamptz AS ends_at
FROM m, jsonb_array_elements(j->'pages') p;

CREATE TEMP TABLE m_reviews AS
SELECT (r->>'event_id')::int AS event_id, (r->>'user_id')::int AS user_id
FROM m, jsonb_array_elements(j->'reviews') r;

DO $$
DECLARE
  orphan_pages int; missing_pages int; stale int; bad_reviews int;
BEGIN
  -- 1. страница без события в PG
  SELECT count(*) INTO orphan_pages
  FROM m_pages mp LEFT JOIN events e ON e.event_id = mp.event_id WHERE e.event_id IS NULL;

  -- 2. событие PG без страницы
  SELECT count(*) INTO missing_pages
  FROM events e LEFT JOIN m_pages mp ON mp.event_id = e.event_id WHERE mp.event_id IS NULL;

  -- 3. устаревший снимок. Mongo хранит время с точностью до миллисекунд.
  SELECT count(*) INTO stale
  FROM m_pages mp JOIN events e ON e.event_id = mp.event_id
  WHERE mp.title  <> e.title
     OR mp.type   <> e.type
     OR mp.status <> e.status
     OR mp.starts_at <> date_trunc('milliseconds', e.datetime)
     OR mp.ends_at   <> date_trunc('milliseconds', e.datetime + e.duration);

  -- 4. отзыв без оплаченного заказа на завершённое событие
  SELECT count(*) INTO bad_reviews
  FROM m_reviews mr
  WHERE NOT EXISTS (
    SELECT 1 FROM orders o JOIN events e ON e.event_id = o.event_id
    WHERE o.event_id = mr.event_id AND o.user_id = mr.user_id
      AND o.status = 'paid' AND e.status = 'finished');

  RAISE NOTICE 'страниц в Mongo: %, отзывов: %',
    (SELECT count(*) FROM m_pages), (SELECT count(*) FROM m_reviews);
  RAISE NOTICE 'страниц без события в PG: %', orphan_pages;
  RAISE NOTICE 'событий PG без страницы: %', missing_pages;
  RAISE NOTICE 'устаревших снимков event: %', stale;
  RAISE NOTICE 'отзывов без оплаченного заказа на завершённое событие: %', bad_reviews;

  IF orphan_pages + missing_pages + stale + bad_reviews > 0 THEN
    RAISE EXCEPTION 'PostgreSQL и MongoDB рассогласованы';
  END IF;
END $$;
