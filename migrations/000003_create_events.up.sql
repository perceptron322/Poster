CREATE TABLE events (
    event_id      INTEGER GENERATED ALWAYS AS IDENTITY,
    title         VARCHAR(300)  NOT NULL,
    description   TEXT,
    cover         VARCHAR(500),
    datetime      TIMESTAMPTZ   NOT NULL,
    duration      INTERVAL      NOT NULL,
    type          VARCHAR(50)   NOT NULL,
    ticket_price  NUMERIC(10,2) NOT NULL,
    status        VARCHAR(20)   NOT NULL DEFAULT 'published',

    user_id       INTEGER NOT NULL,
    location_id   INTEGER NOT NULL,

    CONSTRAINT pk_events PRIMARY KEY (event_id),

    -- Опорный ключ для составного FK из location_bookings:
    -- гарантирует, что бронь ссылается на ту же площадку, что и мероприятие.
    CONSTRAINT uq_events_id_location UNIQUE (event_id, location_id),

    CONSTRAINT fk_events_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_events_location
        FOREIGN KEY (location_id) REFERENCES locations(location_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_events_price    CHECK (ticket_price > 0),
    CONSTRAINT chk_events_duration CHECK (duration > INTERVAL '0'),
    CONSTRAINT chk_events_status
        CHECK (status IN ('published', 'cancelled', 'finished'))
);

COMMENT ON COLUMN events.user_id     IS 'Организатор мероприятия';
COMMENT ON COLUMN events.location_id IS 'Площадка проведения';

-- Запрет на создание мероприятия в прошлом.
-- Дата проверяется только при вставке или при её фактическом изменении,
-- иначе любой UPDATE прошедшего мероприятия (например, перевод в 'finished')
-- блокировался бы триггером.
CREATE OR REPLACE FUNCTION check_event_not_past() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.datetime IS DISTINCT FROM OLD.datetime THEN
        IF NEW.datetime < now() THEN
            RAISE EXCEPTION 'event datetime is in the past';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_events_not_past
BEFORE INSERT OR UPDATE ON events
FOR EACH ROW EXECUTE FUNCTION check_event_not_past();
