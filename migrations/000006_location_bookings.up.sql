CREATE TABLE location_bookings (
    booking_id SERIAL PRIMARY KEY,
    location_id INT NOT NULL,
    event_id INT NOT NULL UNIQUE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    CHECK (end_time > start_time),
    FOREIGN KEY (location_id) REFERENCES locations(location_id) ON DELETE RESTRICT,
    FOREIGN KEY (event_id, location_id)
        REFERENCES events(event_id, location_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
