BEGIN;
INSERT INTO users (name, email, role) VALUES ('Двойник', 'alice@example.com', 'customer');
INSERT INTO users (name, email, role) VALUES ('Тройник', 'alice@example.com', 'customer');
ROLLBACK;
