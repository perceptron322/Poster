#!/bin/sh
#   up       поднять стенд и дождаться healthy
#   status   роли узлов и состояние потоковой репликации
#   lsn      LSN на primary и replica, отставание в байтах и времени
#   restart  перезапустить replica и дождаться streaming
#   rebuild  пересоздать replica с нуля (новый pg_basebackup)
#   test     автотесты репликации
#   logs     последние логи узлов
#   down     остановить стенд (тома сохраняются)
#   clean    остановить стенд и удалить его тома
set -eu

dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/../.." && pwd)

if [ ! -f "$dir/.env" ]; then
    sh "$root/scripts/env-init.sh" "$dir/.env.example" "$dir/.env"
fi

# Значения стенда должны перекрывать переменные корневого .env,
# которые Makefile экспортирует (например POSTGRES_DB=poster):
# docker compose отдаёт приоритет окружению над --env-file.
set -a
. "$dir/.env"
set +a

compose() {
    docker compose -f "$dir/compose.yaml" --env-file "$dir/.env" "$@"
}

psql_on() {
    node=$1
    shift
    compose exec -T "$node" psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" \
        -v ON_ERROR_STOP=1 -X -q "$@"
}

value_on() {
    psql_on "$1" -tA -c "$2"
}

# Ждёт, пока на primary появится реплика в состоянии streaming.
wait_streaming() {
    i=0
    until [ "$(value_on primary "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'" 2>/dev/null)" = "1" ]; do
        i=$((i + 1))
        if [ "$i" -ge 30 ]; then
            echo "replica не перешла в streaming за 60 с" >&2
            return 1
        fi
        sleep 2
    done
}

cmd_up() {
    compose up -d --wait primary replica
    wait_streaming
    compose ps
}

cmd_status() {
    echo "== primary =="
    psql_on primary -f /course/sql/01-primary-status.sql
    echo "== replica =="
    psql_on replica -f /course/sql/03-replica-status.sql
}

cmd_lsn() {
    echo "== primary =="
    psql_on primary -c "
SELECT pg_current_wal_lsn() AS current_lsn;
SELECT application_name, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;"
    echo "== replica =="
    psql_on replica -c "
SELECT pg_last_wal_receive_lsn() AS receive_lsn,
       pg_last_wal_replay_lsn() AS replay_lsn,
       greatest(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()), 0) AS unapplied_bytes,
       pg_last_xact_replay_timestamp() AS last_replayed_xact_at;"
}

cmd_restart() {
    compose restart replica
    compose up -d --wait replica
    wait_streaming
    echo "репликация восстановлена"
    cmd_lsn
}

cmd_rebuild() {
    compose rm -fsv replica
    docker volume rm -f sprint04_replica_data >/dev/null
    compose up -d --wait replica
    wait_streaming
    echo "replica пересоздана из свежего base backup"
    cmd_lsn
}

failed=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; failed=1; }

cmd_test() {
    echo "== 1. Роли узлов =="
    [ "$(value_on primary 'SELECT pg_is_in_recovery()')" = "f" ] \
        && pass "primary не в recovery" || fail "primary в режиме recovery"
    [ "$(value_on replica 'SELECT pg_is_in_recovery()')" = "t" ] \
        && pass "replica в recovery (hot standby)" || fail "replica не в режиме recovery"

    echo "== 2. Потоковая репликация =="
    state=$(value_on primary "SELECT state || '/' || sync_state FROM pg_stat_replication WHERE application_name = 'course_replica'")
    [ "$state" = "streaming/async" ] \
        && pass "course_replica: $state" || fail "ожидалось streaming/async, получено '$state'"

    echo "== 3. Запись на primary доходит до replica =="
    marker="ha-test-$(date +%Y%m%d-%H%M%S)-$$"
    value_on primary "INSERT INTO app.replication_probe (marker) VALUES ('$marker')" >/dev/null
    lsn=$(value_on primary 'SELECT pg_current_wal_lsn()')
    i=0
    until [ "$(value_on replica "SELECT pg_last_wal_replay_lsn() >= '$lsn'")" = "t" ] || [ "$i" -ge 10 ]; do
        i=$((i + 1))
        sleep 1
    done
    [ "$(value_on replica "SELECT count(*) FROM app.replication_probe WHERE marker = '$marker'")" = "1" ] \
        && pass "запись $marker видна на replica (LSN $lsn)" || fail "запись $marker не появилась на replica"

    echo "== 4. Запись на replica запрещена =="
    if out=$(value_on replica "INSERT INTO app.replication_probe (marker) VALUES ('must-fail-$marker')" 2>&1); then
        fail "INSERT на replica выполнился"
    else
        case "$out" in
            *read-only*) pass "INSERT отклонён: read-only transaction" ;;
            *) fail "INSERT упал не по read-only: $out" ;;
        esac
    fi

    echo "== 5. Данные на узлах совпадают =="
    sql="SELECT count(*) || ':' || coalesce(max(id), 0) || ':' || md5(coalesce(string_agg(marker, ',' ORDER BY id), '')) FROM app.replication_probe"
    p=$(value_on primary "$sql")
    r=$(value_on replica "$sql")
    [ "$p" = "$r" ] && pass "app.replication_probe совпадает ($p)" || fail "primary=$p replica=$r"
    [ "$(value_on replica 'SELECT count(*) FROM (SELECT marker FROM app.replication_probe GROUP BY marker HAVING count(*) > 1) d')" = "0" ] \
        && pass "дубликатов marker нет" || fail "на replica есть дубликаты marker"

    echo
    if [ "$failed" -eq 0 ]; then
        echo "✅ Все тесты репликации прошли"
    else
        echo "❌ Есть проваленные тесты"
        exit 1
    fi
}

case "${1:-}" in
    up) cmd_up ;;
    status) cmd_status ;;
    lsn) cmd_lsn ;;
    restart) cmd_restart ;;
    rebuild) cmd_rebuild ;;
    test) cmd_test ;;
    logs) compose logs --tail=100 primary replica ;;
    down) compose down ;;
    clean) compose --profile restore down -v ;;
    *)
        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
