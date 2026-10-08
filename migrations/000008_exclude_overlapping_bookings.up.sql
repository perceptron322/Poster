-- Запрещаем двум бронированиям одной площадки пересекаться во времени.
-- Это ключевое бизнес-правило: одна площадка не может быть занята
-- в один момент двумя мероприятиями.
--
-- Требует btree_gist: без него GiST не умеет работать с equality
-- по скалярным типам (int) в паре с range-типом.
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE location_bookings
  ADD CONSTRAINT ex_bookings_no_overlap
  EXCLUDE USING GIST (
    location_id WITH =,
    tstzrange(start_time, end_time) WITH &&
  );