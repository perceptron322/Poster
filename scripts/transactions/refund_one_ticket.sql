BEGIN;

UPDATE tickets
SET status = 'returned'
WHERE ticket_id = (
    SELECT ticket_id
    FROM tickets
    WHERE order_id = 1 AND status = 'valid'
    ORDER BY ticket_id
    LIMIT 1
);

UPDATE orders
SET total_price = COALESCE((
    SELECT SUM(price)
    FROM tickets
    WHERE order_id = 1 AND status = 'valid'
), 0)
WHERE order_id = 1;

COMMIT;

-- Бизнес-задача:
--   Покупатель возвращает один билет из заказа.
--   Транзакция меняет ДВЕ связанные таблицы: tickets и orders.
--
-- Параметры:
--   order_id — id заказа. В примере 1.
--
-- Шаги:
--   1) Один активный билет заказа переводится в статус 'returned'.
--   2) total_price заказа пересчитывается как сумма активных
--      билетов. COALESCE(..., 0) нужен на случай, если активных
--      билетов не осталось.
--
-- Почему транзакция:
--   Между шагами 1 и 2 сумма заказа временно не совпадает
--   с реальной суммой активных билетов. Если процесс упадёт
--   посередине, БД останется в противоречивом состоянии.
--   Транзакция гарантирует либо оба шага применяются,
--   либо ни один.