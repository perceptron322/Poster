#!/usr/bin/env bash
set -euo pipefail

CONTAINERS=(
  poster-mongo-rs1
  poster-mongo-rs2
  poster-mongo-rs3
)

URI="mongodb://mongo-rs1:27017,mongo-rs2:27017,mongo-rs3:27017/?replicaSet=posterRS"
STOPPED=""

# Если сценарий завершится с ошибкой, возвращаем остановленный узел.
cleanup() {
  if [[ -n "$STOPPED" ]]; then
    echo "Восстанавливаем узел $STOPPED..."
    docker start "$STOPPED" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

get_primary() {
  for c in "${CONTAINERS[@]}"; do
    p=$(docker exec "$c" mongosh --quiet --eval 'db.hello().primary' 2>/dev/null || true)
    if [[ -n "$p" && "$p" != "null" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

echo "Определяем текущий Primary..."
PRIMARY=$(get_primary || true)

if [[ -z "$PRIMARY" ]]; then
  echo "ОШИБКА: не удалось определить Primary"
  exit 1
fi

PRIMARY_HOST="${PRIMARY%%:*}"
STOPPED="poster-${PRIMARY_HOST}"

echo "Текущий Primary: $PRIMARY"
echo "Останавливаем контейнер: $STOPPED"
docker stop "$STOPPED" >/dev/null

echo "Ожидаем выборов нового Primary..."

NEW_PRIMARY=""

for i in {1..60}; do
  NEW_PRIMARY=$(get_primary || true)

  if [[ -n "$NEW_PRIMARY" && "$NEW_PRIMARY" != "$PRIMARY" ]]; then
    break
  fi

  sleep 2
done

if [[ -z "$NEW_PRIMARY" || "$NEW_PRIMARY" == "$PRIMARY" ]]; then
  echo "ОШИБКА: новый Primary не выбран"
  exit 1
fi

echo "Новый Primary: $NEW_PRIMARY"

# Выбираем любой работающий узел, кроме остановленного.
CLIENT=""

for c in "${CONTAINERS[@]}"; do
  if [[ "$c" != "$STOPPED" ]] && docker exec "$c" mongosh --quiet --eval 'db.hello().ok' >/dev/null 2>&1; then
    CLIENT="$c"
    break
  fi
done

if [[ -z "$CLIENT" ]]; then
  echo "ОШИБКА: не найден доступный узел для подключения"
  exit 1
fi

echo "Подключаемся через $CLIENT и проверяем запись..."

docker exec "$CLIENT" mongosh "$URI" --quiet --eval '
const demo = db.getSiblingDB("poster_failover_demo");
const doc = {event: "automated_failover", time: new Date()};
const result = demo.checks.insertOne(
  doc,
  {writeConcern: {w: "majority", wtimeout: 10000}}
);
print("Результат записи:");
printjson(result);

const saved = demo.checks.findOne({_id: result.insertedId});
if (!saved) {
  print("ОШИБКА: запись не найдена");
  quit(2);
}

print("Запись проверена:");
printjson(saved);
print("Текущий Primary: " + db.hello().primary);
'

echo "Возвращаем остановленный узел..."
docker start "$STOPPED" >/dev/null
STOPPED=""

echo "Ожидаем возвращения узла в Replica Set..."

STATE="UNKNOWN"

for i in {1..60}; do
  STATE=$(docker exec "$CLIENT" mongosh --quiet --eval "
    const m = rs.status().members.find(x => x.name === '${PRIMARY_HOST}:27017');
    print(m ? m.stateStr : 'UNKNOWN');
  " 2>/dev/null || echo "UNKNOWN")

  if [[ "$STATE" == "SECONDARY" || "$STATE" == "PRIMARY" ]]; then
    break
  fi

  sleep 2
done

if [[ "$STATE" != "SECONDARY" && "$STATE" != "PRIMARY" ]]; then
  echo "ОШИБКА: узел не вернулся в Replica Set"
  exit 1
fi

echo "Восстановленный узел: $PRIMARY_HOST ($STATE)"
echo "Итоговое состояние Replica Set:"

docker exec "$CLIENT" mongosh --quiet --eval '
rs.status().members.forEach(m => print(m.name + " " + m.stateStr));
'

echo "УСПЕХ: отказ Primary, запись и восстановление узла проверены."
