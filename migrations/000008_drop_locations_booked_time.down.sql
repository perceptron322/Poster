ALTER TABLE locations ADD COLUMN booked_time TSTZRANGE;
CREATE INDEX idx_locations_booked_time ON locations USING GIST (booked_time);