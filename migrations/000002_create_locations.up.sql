CREATE TABLE locations (
    location_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    address VARCHAR(500) NOT NULL,
    capacity INT NOT NULL CHECK (capacity > 0)
);
