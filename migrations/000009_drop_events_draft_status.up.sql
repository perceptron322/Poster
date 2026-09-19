ALTER TABLE events DROP CONSTRAINT IF EXISTS chk_events_status;
ALTER TABLE events ADD CONSTRAINT chk_events_status
    CHECK (status IN ('published', 'cancelled', 'finished'));
ALTER TABLE events ALTER COLUMN status SET DEFAULT 'published';