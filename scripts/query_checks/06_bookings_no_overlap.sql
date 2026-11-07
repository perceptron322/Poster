DO $$
BEGIN
  IF EXISTS (
      SELECT 1 FROM (
          SELECT lb.start_time,
                 LAG(lb.end_time) OVER (PARTITION BY lb.location_id ORDER BY lb.start_time) AS prev_end
          FROM location_bookings lb
      ) s
      WHERE prev_end IS NOT NULL AND prev_end > s.start_time
  ) THEN
      RAISE EXCEPTION 'Провал 06: бронирования одной площадки пересекаются во времени (запрос 08)';
  END IF;
  RAISE NOTICE '✅ 06: наложений бронирований нет (запрос 08)';
END $$;