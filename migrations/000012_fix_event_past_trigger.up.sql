-- Проверять дату только при вставке или при её фактическом изменении,
-- иначе любой UPDATE прошедшего мероприятия (например, перевод в 'finished')
-- блокируется триггером.
CREATE OR REPLACE FUNCTION check_event_not_past() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.datetime IS DISTINCT FROM OLD.datetime THEN
        IF NEW.datetime < now() THEN
            RAISE EXCEPTION 'event datetime is in the past';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
