CREATE TABLE users (
    user_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name     VARCHAR(200) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    role     VARCHAR(20)  NOT NULL DEFAULT 'customer',

    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT chk_users_role
        CHECK (role IN ('customer', 'organizer', 'admin'))
);

COMMENT ON TABLE  users      IS 'Пользователи системы';
COMMENT ON COLUMN users.role IS 'Роль: customer / organizer / admin';