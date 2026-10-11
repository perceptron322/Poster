BEGIN;

-- Создаём заказ покупателя на мероприятие № 1
INSERT INTO orders (user_id, event_id, status, total_price)
VALUES (2, 1, 'paid', 3000.00)
RETURNING order_id \gset

-- Добавляем два билета к заказу
INSERT INTO tickets (price, status, order_id)
VALUES
    (1500.00, 'valid', :order_id),
    (1500.00, 'valid', :order_id);

-- Сохраняем изменения
COMMIT;

-- Проверяем, что заказ и билеты существуют
SELECT order_id, user_id, event_id, status, total_price
FROM orders
WHERE order_id = :order_id;

SELECT ticket_id, price, status, order_id
FROM tickets
WHERE order_id = :order_id;
