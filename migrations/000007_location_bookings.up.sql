CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Таблица броней
CREATE TABLE location_bookings (
    booking_id  INTEGER GENERATED ALWAYS AS IDENTITY,
    location_id INTEGER     NOT NULL,
    event_id    INTEGER     NOT NULL,
    period      TSTZRANGE   NOT NULL,

    CONSTRAINT pk_location_bookings   PRIMARY KEY (booking_id),
    CONSTRAINT fk_bookings_location   FOREIGN KEY (location_id)
        REFERENCES locations(location_id) ON DELETE RESTRICT,

    -- Составной FK: бронь не может указывать на площадку, отличную от
    -- events.location_id. ON UPDATE CASCADE переносит бронь вслед за
    -- переносом мероприятия на другую площадку.
    CONSTRAINT fk_bookings_event      FOREIGN KEY (event_id, location_id)
        REFERENCES events(event_id, location_id)
        ON DELETE CASCADE ON UPDATE CASCADE,

    CONSTRAINT uq_bookings_event      UNIQUE (event_id),
    CONSTRAINT chk_bookings_period    CHECK (NOT isempty(period)),
    CONSTRAINT ex_bookings_no_overlap EXCLUDE USING GIST (
        location_id WITH =,
        period      WITH &&
    )
);

-- Дополнительный индекс по location_id (для JOIN-ов «мероприятия площадки»)
CREATE INDEX idx_bookings_location ON location_bookings(location_id);
