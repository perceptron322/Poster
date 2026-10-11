-- Запоминаем количество записей до транзакции
SELECT COUNT(*) AS orders_before FROM orders;
SELECT COUNT(*) AS tickets_before FROM tickets;

BEGIN;

-- Создаём тестовый заказ
INSERT INTO orders (user_id, event_id, status, total_price)
VALUES (2, 1, 'paid', 1500.00)
RETURNING order_id \gset

-- Добавляем билет
INSERT INTO tickets (price, status, order_id)
VALUES (1500.00, 'valid', :order_id);

-- Проверяем временно созданные данные
SELECT * FROM orders WHERE order_id = :order_id;
SELECT * FROM tickets WHERE order_id = :order_id;

-- Отменяем все изменения транзакции
ROLLBACK;

-- Проверяем, что количество записей не изменилось
SELECT COUNT(*) AS orders_after FROM orders;
SELECT COUNT(*) AS tickets_after FROM tickets;
