CREATE TABLE tickets (
    ticket_id SERIAL PRIMARY KEY,
    price DECIMAL(10,2) NOT NULL CHECK (price > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'valid'
        CHECK (status IN ('valid', 'used', 'returned', 'cancelled')),
    order_id INT NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);
