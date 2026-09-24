CREATE TABLE tickets (
    ticket_id SERIAL PRIMARY KEY,
    price DECIMAL(10,2) NOT NULL CHECK (price > 0),
    status VARCHAR(20) NOT NULL,

    order_id INT NOT NULL,

    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);