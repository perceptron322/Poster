-- Оформление нового заказа: created_at = now().
\set uid random(:umin, :umax)
\set eid random(1, :emax)
INSERT INTO __T__ (status, total_price, user_id, event_id)
VALUES ('pending', 1000, :uid, :eid);
