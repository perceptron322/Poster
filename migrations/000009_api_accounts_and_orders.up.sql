-- Старые пользователи сохраняют свои ID и связи. Вход доступен после
-- создания учётных данных, поэтому seed не получает общих паролей.
CREATE TABLE user_credentials (
    user_id integer PRIMARY KEY REFERENCES users ON DELETE CASCADE,
    password_salt bytea NOT NULL,
    password_hash bytea NOT NULL
);

CREATE TABLE user_sessions (
    token_hash bytea PRIMARY KEY,
    user_id integer NOT NULL REFERENCES users ON DELETE CASCADE,
    expires_at timestamptz NOT NULL
);
CREATE INDEX idx_sessions_expiry ON user_sessions(expires_at);
CREATE INDEX idx_users_email_lower ON users(lower(email));

-- Пять билетов с максимальной допустимой ценой должны помещаться в заказ.
ALTER TABLE orders ALTER COLUMN total_price TYPE numeric(11,2);
ALTER TABLE orders ADD COLUMN purchase_key varchar(128);
CREATE UNIQUE INDEX idx_orders_purchase_key ON orders(user_id, purchase_key)
    WHERE purchase_key IS NOT NULL;

-- Эти роли могли быть заведены до обновления существующей базы.
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname='app_user') THEN
        GRANT SELECT, INSERT ON user_credentials TO app_user;
        GRANT SELECT, INSERT, DELETE ON user_sessions TO app_user;
    END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname='admin_user') THEN
        GRANT ALL ON user_credentials, user_sessions TO admin_user;
    END IF;
END $$;
