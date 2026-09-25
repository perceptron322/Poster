CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    role VARCHAR(20) NOT NULL DEFAULT 'guest'
        CHECK (role IN ('guest', 'customer', 'organizer'))
);
