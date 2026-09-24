CREATE TABLE events (
    event_id SERIAL PRIMARY KEY,
    title VARCHAR(300) NOT NULL,
    description TEXT,
    cover VARCHAR(500),
    datetime TIMESTAMP NOT NULL,
    duration INT NOT NULL CHECK (duration > 0),
    type VARCHAR(50) NOT NULL,
    ticket_price DECIMAL(10,2) NOT NULL CHECK (ticket_price > 0),
    status VARCHAR(20) NOT NULL,

    user_id INT NOT NULL,
    location_id INT NOT NULL,

    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (location_id) REFERENCES locations(location_id)
);