-- Точечный поиск заказа по id. Ключ партицирования не задан ни в одной стратегии.
\set oid random(1, :omax)
SELECT * FROM __T__ WHERE order_id = :oid;
