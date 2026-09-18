CREATE INDEX idx_events_user_id      ON events(user_id);
CREATE INDEX idx_events_location_id  ON events(location_id);
CREATE INDEX idx_orders_user_id      ON orders(user_id);
CREATE INDEX idx_orders_event_id     ON orders(event_id);
CREATE INDEX idx_tickets_order_id    ON tickets(order_id);

CREATE INDEX idx_events_datetime     ON events(datetime);
CREATE INDEX idx_events_status       ON events(status);
CREATE INDEX idx_orders_status       ON orders(status);

CREATE INDEX idx_orders_user_status  ON orders(user_id, status);

CREATE INDEX idx_locations_booked_time
    ON locations USING GIST (booked_time);