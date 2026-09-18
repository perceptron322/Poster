CREATE TABLE events (
    event_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title         VARCHAR(300)  NOT NULL,
    description   TEXT,
    cover         VARCHAR(500),
    datetime      TIMESTAMPTZ   NOT NULL,
    duration      INTERVAL      NOT NULL,
    type          VARCHAR(50)   NOT NULL,
    ticket_price  NUMERIC(10,2) NOT NULL,
    status        VARCHAR(20)   NOT NULL DEFAULT 'draft',

    user_id       INTEGER NOT NULL,
    location_id   INTEGER NOT NULL,

    CONSTRAINT fk_events_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_events_location
        FOREIGN KEY (location_id) REFERENCES locations(location_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_events_price    CHECK (ticket_price >= 0),
    CONSTRAINT chk_events_duration CHECK (duration > INTERVAL '0'),
    CONSTRAINT chk_events_status
        CHECK (status IN ('draft', 'published', 'cancelled', 'finished'))
);

COMMENT ON COLUMN events.user_id     IS 'Организатор мероприятия';
COMMENT ON COLUMN events.location_id IS 'Площадка проведения';