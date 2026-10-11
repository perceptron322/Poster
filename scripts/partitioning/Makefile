PSQL = docker compose -f ../../docker-compose.yml exec -T db psql -U poster -d poster -v ON_ERROR_STOP=1

.PHONY: setup plain range hash stats explain bench clean

setup: plain range hash stats

plain:
	$(PSQL) < 00_plain.sql

range:
	$(PSQL) < 01_range.sql

hash:
	$(PSQL) < 02_hash.sql

stats:
	$(PSQL) < 10_stats.sql

explain:
	$(PSQL) < 20_explain.sql

bench:
	./run_bench.sh

clean:
	$(PSQL) -c 'DROP TABLE IF EXISTS orders_plain, orders_range, orders_hash; DROP SEQUENCE IF EXISTS orders_plain_order_id_seq, orders_range_order_id_seq, orders_hash_order_id_seq;'
