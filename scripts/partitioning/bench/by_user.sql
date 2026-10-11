-- Заказы покупателя (личный кабинет). Выгодно HASH по user_id.
\set uid random(:umin, :umax)
SELECT order_id, created_at, status, total_price, event_id
FROM __T__ WHERE user_id = :uid;
