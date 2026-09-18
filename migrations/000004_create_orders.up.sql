CREATE TABLE orders (
    order_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    status       VARCHAR(20)   NOT NULL DEFAULT 'pending',
    total_price  NUMERIC(10,2) NOT NULL DEFAULT 0,

    user_id      INTEGER NOT NULL,
    event_id     INTEGER NOT NULL,

    CONSTRAINT fk_orders_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_orders_event
        FOREIGN KEY (event_id) REFERENCES events(event_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_orders_total  CHECK (total_price >= 0),
    CONSTRAINT chk_orders_status
        CHECK (status IN ('pending', 'paid', 'cancelled', 'refunded'))
);

COMMENT ON COLUMN orders.user_id  IS 'Покупатель';
COMMENT ON COLUMN orders.event_id IS 'Мероприятие, на которое оформлен заказ';