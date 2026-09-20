-- Вернуть проверку на любом INSERT/UPDATE (версия из 000011)
CREATE OR REPLACE FUNCTION check_event_not_past() RETURNS trigger AS $$
BEGIN
    IF NEW.datetime < now() THEN
        RAISE EXCEPTION 'event datetime is in the past';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
