DROP TRIGGER IF EXISTS trg_events_not_past ON events;
DROP FUNCTION IF EXISTS check_event_not_past();