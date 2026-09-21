CREATE TABLE locations (
    location_id  INTEGER GENERATED ALWAYS AS IDENTITY,
    name         VARCHAR(200) NOT NULL,
    address      VARCHAR(500) NOT NULL,
    capacity     INT          NOT NULL,

    CONSTRAINT pk_locations           PRIMARY KEY (location_id),
    CONSTRAINT chk_locations_capacity CHECK (capacity > 0)
);
