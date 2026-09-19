-- events
ALTER TABLE events DROP CONSTRAINT IF EXISTS chk_events_price;
ALTER TABLE events ADD CONSTRAINT chk_events_price CHECK (ticket_price >= 0);

-- tickets: price
ALTER TABLE tickets DROP CONSTRAINT IF EXISTS chk_tickets_price;
ALTER TABLE tickets ADD CONSTRAINT chk_tickets_price CHECK (price >= 0);

-- tickets: status — вернуть исходный (без returned)
ALTER TABLE tickets DROP CONSTRAINT IF EXISTS chk_tickets_status;
ALTER TABLE tickets ADD CONSTRAINT chk_tickets_status
    CHECK (status IN ('valid', 'used', 'cancelled'));