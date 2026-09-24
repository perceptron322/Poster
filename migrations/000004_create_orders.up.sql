CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    status VARCHAR(20) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL CHECK (total_price >= 0),

    user_id INT NOT NULL,
    event_id INT NOT NULL,

    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (event_id) REFERENCES events(event_id)
);