CREATE TABLE events (
    event_id SERIAL PRIMARY KEY,
    title VARCHAR(300) NOT NULL,
    description TEXT,
    cover VARCHAR(500),
    datetime TIMESTAMPTZ NOT NULL,
    duration INTERVAL NOT NULL CHECK (duration > INTERVAL '0'),
    type VARCHAR(50) NOT NULL
        CHECK (type IN ('concert', 'lecture', 'theatre', 'festival', 'other')),
    ticket_price DECIMAL(10,2) NOT NULL CHECK (ticket_price > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'published'
        CHECK (status IN ('published', 'cancelled', 'finished')),
    user_id INT NOT NULL,
    location_id INT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE RESTRICT,
    FOREIGN KEY (location_id) REFERENCES locations(location_id) ON DELETE RESTRICT,
    UNIQUE (event_id, location_id)
);
