BEGIN;
INSERT INTO users (name, email, role) VALUES ('Двойник', 'alice@example.com', 'customer');
ROLLBACK;
