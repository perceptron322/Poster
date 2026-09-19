CREATE OR REPLACE FUNCTION check_event_not_past() RETURNS trigger AS $$
BEGIN
    IF NEW.datetime < now() THEN
        RAISE EXCEPTION 'event datetime is in the past';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_events_not_past
BEFORE INSERT OR UPDATE ON events
FOR EACH ROW EXECUTE FUNCTION check_event_not_past();