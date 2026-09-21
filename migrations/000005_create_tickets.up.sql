CREATE TABLE tickets (
    ticket_id  INTEGER GENERATED ALWAYS AS IDENTITY,
    price      NUMERIC(10,2) NOT NULL,
    status     VARCHAR(20)   NOT NULL DEFAULT 'valid',

    order_id   INTEGER NOT NULL,

    CONSTRAINT pk_tickets PRIMARY KEY (ticket_id),

    CONSTRAINT fk_tickets_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_tickets_price  CHECK (price > 0),
    CONSTRAINT chk_tickets_status
        CHECK (status IN ('valid', 'used', 'returned', 'cancelled'))
);

COMMENT ON COLUMN tickets.order_id IS 'Заказ, к которому относится билет';
