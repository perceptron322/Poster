DROP TABLE IF EXISTS bulk_load_benchmark;

CREATE TABLE bulk_load_benchmark (
    id BIGINT PRIMARY KEY,
    name TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
