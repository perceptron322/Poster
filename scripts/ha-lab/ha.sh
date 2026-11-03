#!/bin/sh
set -eu

# up       запустить стенд и инициализировать базу
# status   показать доступные узлы и состояние репликации
# lsn      показать LSN и отставание
# restart  перезапустить текущую реплику
# rebuild  пересоздать текущую реплику с нуля (с подтверждением)
# test     проверить репликацию и read-only на реплике
# logs     показать логи стенда
# down     остановить стенд, сохранив тома
# clean    удалить тома стенда после подтверждения

dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/../.." && pwd)

if [ ! -f "$dir/.env" ]; then
    sh "$root/scripts/env-init.sh" "$dir/.env.example" "$dir/.env"
fi

set -a
. "$dir/.env"
set +a

# Ограничения времени выполнения.
EXEC_TIMEOUT=5
CURL_TIMEOUT=3
SQL_TIMEOUT=10
WAIT_ATTEMPTS=60
WAIT_INTERVAL=2
COMPOSE_TIMEOUT=30
# Сборка образа и ожидание healthcheck занимают заметно дольше.
UP_TIMEOUT=600

compose() {
    timeout "${COMPOSE_TIMEOUT}s" docker compose \
        -f "$dir/compose.yaml" \
        --env-file "$dir/.env" \
        "$@"
}

nodes="patroni1 patroni2"

# Проверить, доступна ли роль Patroni на конкретном узле.
# Не позволяем Docker exec или curl зависнуть бесконечно.
is_role() {
    node=$1
    role=$2

    timeout "${EXEC_TIMEOUT}s" docker compose \
        -f "$dir/compose.yaml" \
        --env-file "$dir/.env" \
        exec -T "$node" \
        curl --max-time "$CURL_TIMEOUT" -fsS \
        "http://127.0.0.1:8008/$role" </dev/null >/dev/null 2>&1
}

# Найти действующий primary среди доступных узлов.
leader_node() {
    for node in $nodes; do
        if is_role "$node" primary; then
            echo "$node"
            return 0
        fi
    done

    return 1
}

replica_node() {
    for node in $nodes; do
        if is_role "$node" replica; then
            echo "$node"
            return 0
        fi
    done

    return 1
}

# Выполнить SQL на узле с ограничением времени.
psql_on() {
    node=$1
    shift

    timeout "${SQL_TIMEOUT}s" docker compose \
        -f "$dir/compose.yaml" \
        --env-file "$dir/.env" \
        exec -T "$node" \
        psql \
        -U "$POSTGRES_ADMIN_USER" \
        -d "$POSTGRES_DB" \
        -v ON_ERROR_STOP=1 \
        -X -q "$@" </dev/null
}


value_on() {
    psql_on "$1" -tA -c "$2"
}

# Строгая проверка: для репликационных операций нужны оба узла.
wait_roles() {
    attempt=0

    while [ "$attempt" -lt "$WAIT_ATTEMPTS" ]; do
        leader=$(leader_node 2>/dev/null || true)
        replica=$(replica_node 2>/dev/null || true)

        if [ -n "$leader" ] && [ -n "$replica" ]; then
            echo "Лидер: $leader; реплика: $replica"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep "$WAIT_INTERVAL"
    done

    echo "Ошибка: за 120 секунд не удалось определить лидера и реплику." >&2
    compose ps || true
    return 1
}

# Дождаться восстановления потоковой репликации.
wait_streaming() {
    attempt=0

    while [ "$attempt" -lt "$WAIT_ATTEMPTS" ]; do
        leader=$(leader_node 2>/dev/null || true)
        replica=$(replica_node 2>/dev/null || true)

        if [ -n "$leader" ] && [ -n "$replica" ]; then
            count=$(value_on "$leader" \
                "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'" \
                2>/dev/null || true)

            if [ "$count" = "1" ]; then
                echo "Потоковая репликация работает."
                return 0
            fi
        fi

        attempt=$((attempt + 1))
        sleep "$WAIT_INTERVAL"
    done

    echo "Ошибка: репликация не перешла в streaming за 120 секунд." >&2
    return 1
}

cmd_up() {
    COMPOSE_TIMEOUT=$UP_TIMEOUT
    compose up -d --build --wait etcd patroni1 patroni2 haproxy
    COMPOSE_TIMEOUT=30

    wait_roles

    compose --profile tools run --rm init-db
    wait_streaming

    compose ps
}

# Статус должен работать и при остановленном узле.
# В отличие от wait_roles(), наличие реплики не обязательно.
cmd_status() {
    echo "== ПОИСК ЛИДЕРА =="

    leader=$(leader_node 2>/dev/null || true)

    if [ -z "$leader" ]; then
        echo "ОШИБКА: доступный лидер не найден." >&2
        echo
        echo "== СОСТОЯНИЕ КОНТЕЙНЕРОВ =="

        compose ps || true
        return 1
    fi

    replica=$(replica_node 2>/dev/null || true)

    echo "Лидер: $leader"

    if [ -n "$replica" ]; then
        echo "Реплика: $replica"
        echo "Состояние кластера: оба узла доступны"
    else
        echo "Реплика: не обнаружена"
        echo "Состояние кластера: DEGRADED"
        echo "Внимание: лидер работает, но доступная реплика не найдена."
    fi

    echo
    echo "== SQL-СТАТУС ЛИДЕРА: $leader =="

    if ! psql_on "$leader" -f /course/sql/01-primary-status.sql; then
        echo "Ошибка получения SQL-статуса лидера." >&2
        return 1
    fi

    if [ -n "$replica" ]; then
        echo
        echo "== SQL-СТАТУС РЕПЛИКИ: $replica =="

        if ! psql_on "$replica" -f /course/sql/03-replica-status.sql; then
            echo "Ошибка получения SQL-статуса реплики." >&2
            return 1
        fi
    fi

    echo
    echo "== PATRONI API =="

    for node in $nodes; do
        printf '%s: ' "$node"


        if timeout "${EXEC_TIMEOUT}s" docker compose \
            -f "$dir/compose.yaml" \
            --env-file "$dir/.env" \
            exec -T "$node" \
            curl --max-time "$CURL_TIMEOUT" -fsS \
            http://127.0.0.1:8008/patroni \
            </dev/null 2>/dev/null; then
            echo
        else
            echo "недоступен"
        fi

    done

    echo
    echo "== СОСТОЯНИЕ КОНТЕЙНЕРОВ =="

    compose ps
}

cmd_lsn() {
    wait_roles

    leader=$(leader_node)
    replica=$(replica_node)

    echo "== ЛИДЕР: $leader =="

    psql_on "$leader" -c "
SELECT pg_current_wal_lsn() AS current_lsn;

SELECT application_name, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;"

    echo
    echo "== РЕПЛИКА: $replica =="

    psql_on "$replica" -c "
SELECT pg_last_wal_receive_lsn() AS receive_lsn,
       pg_last_wal_replay_lsn() AS replay_lsn,
       greatest(
           pg_wal_lsn_diff(
               pg_last_wal_receive_lsn(),
               pg_last_wal_replay_lsn()
           ), 0
       ) AS unapplied_bytes,
       pg_last_xact_replay_timestamp() AS last_replayed_xact_at;"
}

cmd_restart() {
    wait_roles

    replica=$(replica_node)

    echo "Перезапускаем реплику $replica..."

    compose restart "$replica"

    wait_roles
    wait_streaming
    cmd_lsn
}

cmd_rebuild() {
    wait_roles

    replica=$(replica_node)

    case "$replica" in
        patroni1)
            volume=sprint04_patroni1_data
            ;;
        patroni2)
            volume=sprint04_patroni2_data
            ;;
        *)
            echo "Неизвестный узел реплики." >&2
            return 1
            ;;
    esac

    echo "ВНИМАНИЕ: будут удалены данные узла $replica ($volume)."
    echo "Лидер и его том удаляться не будут."
    printf 'Для продолжения введи REBUILD: '

    read answer

    [ "$answer" = "REBUILD" ] || {
        echo "Отменено."
        return 1
    }

    compose stop "$replica"
    compose rm -f "$replica"
    docker volume rm "$volume"
    compose up -d --build --wait "$replica"

    wait_roles
    wait_streaming
    cmd_lsn
}

failed=0

pass() {
    echo "  PASS: $1"
}

fail() {
    echo "  FAIL: $1"
    failed=1
}

cmd_test() {
    wait_roles

    leader=$(leader_node)
    replica=$(replica_node)

    echo "== 1. Проверка ролей =="

    if [ "$(value_on "$leader" 'SELECT pg_is_in_recovery()')" = "f" ]; then
        pass "$leader является лидером"
    else
        fail "$leader не является лидером"
    fi

    if [ "$(value_on "$replica" 'SELECT pg_is_in_recovery()')" = "t" ]; then
        pass "$replica находится в recovery"
    else
        fail "$replica не находится в recovery"
    fi

    echo "== 2. Потоковая репликация =="

    state=$(value_on "$leader" \
        "SELECT state FROM pg_stat_replication WHERE state = 'streaming'" \
        2>/dev/null || true)

    if [ "$state" = "streaming" ]; then
        pass "соединение репликации активно"
    else
        fail "нет активного соединения репликации"
    fi

    echo "== 3. Запись на лидере появляется на реплике =="

    marker="ha-test-$(date +%Y%m%d-%H%M%S)-$$"

    if ! value_on "$leader" \
        "INSERT INTO app.replication_probe (marker) VALUES ('$marker')" \
        >/dev/null; then
        fail "не удалось записать тестовую запись на лидере"
    else
        attempt=0
        found=""

        while [ "$attempt" -lt 15 ]; do
            found=$(value_on "$replica" \
                "SELECT count(*) FROM app.replication_probe WHERE marker = '$marker'" \
                2>/dev/null || true)

            [ "$found" = "1" ] && break

            attempt=$((attempt + 1))
            sleep 1
        done

        if [ "$found" = "1" ]; then
            pass "запись реплицирована"
        else
            fail "запись не появилась на реплике"
        fi
    fi

    echo "== 4. Запись на реплике запрещена =="

    if output=$(value_on "$replica" \
        "INSERT INTO app.replication_probe (marker) VALUES ('must-fail-$marker')" \
        2>&1); then
        fail "INSERT на реплике неожиданно прошёл"
    else
        case "$output" in
            *"read-only"*)
                pass "запись отклонена в read-only режиме"
                ;;
            *)
                fail "ошибка не связана с read-only: $output"
                ;;
        esac
    fi

    echo

    if [ "$failed" -eq 0 ]; then
        echo "Все тесты пройдены."
    else
        echo "Есть проваленные тесты." >&2
        return 1
    fi
}

cmd_logs() {
    compose logs --tail=100 etcd patroni1 patroni2 haproxy
}

cmd_clean() {
    echo "Будут удалены тома HA-стенда, включая данные Patroni и etcd."
    echo "Рабочая база poster-db в этот Compose-проект не входит."
    printf 'Для подтверждения введи DELETE-HA-DATA: '

    read answer

    [ "$answer" = "DELETE-HA-DATA" ] || {
        echo "Отменено."
        return 1
    }

    compose --profile tools --profile restore down

    docker volume rm \
        sprint04_etcd_data \
        sprint04_patroni1_data \
        sprint04_patroni2_data \
        sprint04_restore_data 2>/dev/null || true
}

case "${1:-}" in
    up)
        cmd_up
        ;;
    status)
        cmd_status
        ;;
    lsn)
        cmd_lsn
        ;;
    restart)
        cmd_restart
        ;;
    rebuild)
        cmd_rebuild
        ;;
    test)
        cmd_test
        ;;
    logs)
        cmd_logs
        ;;
    down)
        compose --profile tools --profile restore down
        ;;
    clean)
        cmd_clean
        ;;
    *)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
