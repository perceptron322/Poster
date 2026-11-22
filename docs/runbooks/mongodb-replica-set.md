# MongoDB Replica Set — участник №4

## 1. Цель работы

Развернуть кластер MongoDB из трёх узлов, настроить Replica Set, проверить автоматическое переключение основного узла при отказе, экспериментально изучить приоритеты участников и проверить параметры согласованности чтения и записи.

## 2. Архитектура

Используется Replica Set с именем `posterRS`, состоящий из трёх узлов:

| Узел | Адрес внутри Docker | Начальный приоритет |
|---|---|---:|
| mongo-rs1 | mongo-rs1:27017 | 2 |
| mongo-rs2 | mongo-rs2:27017 | 1 |
| mongo-rs3 | mongo-rs3:27017 | 1 |

Узел с наибольшим приоритетом предпочтителен для избрания Primary, если он доступен и соответствует условиям выборов.

Состояния участников:
- **PRIMARY** — основной узел, принимающий операции записи.
- **SECONDARY** — вторичный узел, получающий изменения от Primary и поддерживающий копию данных.

## 3. Запуск Replica Set

Запуск контейнеров:

```bash
docker compose -f docker-compose.mongo-rs.yml up -d
```

Проверка состояния контейнеров:

```bash
docker compose -f docker-compose.mongo-rs.yml ps
```

Проверка состояния участников:

```bash
docker exec poster-mongo-rs1 mongosh --quiet --eval \
'rs.status().members.forEach(m=>print(m.name+" "+m.stateStr))'
```

Инициализация Replica Set при первом запуске:

```javascript
rs.initiate({
  _id: "posterRS",
  members: [
    {_id: 0, host: "mongo-rs1:27017", priority: 2},
    {_id: 1, host: "mongo-rs2:27017", priority: 1},
    {_id: 2, host: "mongo-rs3:27017", priority: 1}
  ]
})
```

Инициализацию повторно выполнять не требуется, если Replica Set уже создан.

## 4. Проверка автоматического переключения Primary

Для проверки отказоустойчивости был остановлен контейнер текущего основного узла:

```bash
docker stop poster-mongo-rs1
```

После остановки узла остальные участники провели выборы. Основным узлом стал `mongo-rs2`.

Проверка:

```bash
docker exec poster-mongo-rs2 mongosh --quiet --eval \
'rs.status().members.forEach(m=>print(m.name+" "+m.stateStr))'
```

После восстановления контейнера:

```bash
docker start poster-mongo-rs1
```

Узел повторно присоединился к Replica Set в состоянии SECONDARY. Позже, после восстановления исходных приоритетов и проведения выборов, `mongo-rs1` снова стал PRIMARY.

**Результат:** автоматическое переключение основного узла при отказе успешно продемонстрировано.

## 5. Эксперимент с приоритетами участников

Для проверки влияния параметра `priority` были изменены приоритеты участников:

```javascript
cfg = rs.conf();

cfg.members[0].priority = 1;
cfg.members[1].priority = 3;
cfg.members[2].priority = 1;

rs.reconfig(cfg);
```

После изменения конфигурации основным узлом стал `mongo-rs2`.

Проверка:

```javascript
rs.status().members.forEach(m=>print(m.name+" "+m.stateStr))
```

Затем были восстановлены исходные приоритеты:

```javascript
cfg = rs.conf();

cfg.members[0].priority = 2;
cfg.members[1].priority = 1;
cfg.members[2].priority = 1;

rs.reconfig(cfg);
```

После этого `mongo-rs1` снова стал PRIMARY.

**Вывод:** параметр `priority` влияет на предпочтительность узла при выборах Primary. Он не гарантирует немедленное переключение при любых обстоятельствах.

## 6. Проверка сохранности данных после отказа

Для проверки использовалась база `poster_failover_demo` и коллекция `checks`.

До отказа Primary была выполнена запись:

```javascript
db.getSiblingDB("poster_failover_demo").checks.insertOne({
  event: "initial_write",
  time: new Date()
});
```

После остановки `mongo-rs1` и избрания `mongo-rs2` новым Primary была выполнена вторая запись:

```javascript
db.getSiblingDB("poster_failover_demo").checks.insertOne({
  event: "write_after_failover",
  time: new Date()
});
```

Обе операции завершились успешно. После повторного запуска `mongo-rs1` обе записи были доступны.

**Результат:** подключение к Replica Set позволило продолжить запись после переключения основного узла без ручного изменения адреса подключения.

## 7. Автоматизация отказа и восстановления

Для автоматической проверки создан скрипт:

```
scripts/mongo-rs/failover-demo.sh
```

Запуск:

```bash
./scripts/mongo-rs/failover-demo.sh
```

Сценарий выполняет следующие действия:

1. Определяет текущий PRIMARY.
2. Останавливает контейнер основного узла.
3. Ожидает избрания нового PRIMARY.
4. Подключается к Replica Set через строку с адресами всех трёх узлов.
5. Выполняет тестовую запись с подтверждением majority.
6. Проверяет наличие созданного документа.
7. Запускает остановленный контейнер.
8. Ожидает возвращения участника в Replica Set.
9. Выводит итоговое состояние всех трёх узлов.

**Результат:** автоматический сценарий успешно выполнился. После отказа `mongo-rs1` новым PRIMARY стал `mongo-rs2`, запись прошла успешно, а восстановленный `mongo-rs1` вернулся в состояние SECONDARY.

## 8. Проверка параметров согласованности

### 8.1. writeConcern

Проверка записи с подтверждением большинства:

```javascript
db.checks.insertOne(
  {event: "concern_test", time: new Date()},
  {writeConcern: {w: "majority", wtimeout: 10000}}
);
```

Параметр `w: "majority"` требует подтверждения записи большинством голосующих участников Replica Set.

### 8.2. readConcern

Проверка чтения с уровнем majority:

```javascript
db.runCommand({
  find: "checks",
  filter: {event: "concern_test"},
  readConcern: {level: "majority"}
});
```

Уровень `majority` позволяет читать данные, подтверждённые большинством участников.

### 8.3. readPreference

Режим `secondaryPreferred`:

```
mongodb://mongo-rs1:27017,mongo-rs2:27017,mongo-rs3:27017/?replicaSet=posterRS&readPreference=secondaryPreferred
```

Этот режим предпочитает чтение со вторичных узлов, но допускает чтение с PRIMARY, если подходящие SECONDARY недоступны.

Режим `primary`:

```
mongodb://mongo-rs1:27017,mongo-rs2:27017,mongo-rs3:27017/?replicaSet=posterRS&readPreference=primary
```

В этом режиме чтение выполняется только с основного узла.

Проверки обоих режимов завершились успешно.

## 9. Итоговые результаты

В ходе работы:

- Развёрнут Replica Set из трёх узлов MongoDB.
- Проверено распределение ролей PRIMARY и SECONDARY.
- Продемонстрировано автоматическое переключение Primary при остановке узла.
- Выполнен эксперимент с изменением приоритетов участников.
- Проверена запись данных после отказа основного узла.
- Создан и успешно запущен сценарий автоматизации отказа и восстановления.
- Проверены настройки `writeConcern`, `readConcern` и `readPreference`.

Таким образом, реализованная конфигурация демонстрирует базовые механизмы отказоустойчивости MongoDB Replica Set.

## 10. Остановка окружения

Остановка контейнеров:

```bash
docker compose -f docker-compose.mongo-rs.yml down
```

Для удаления томов с данными можно использовать `-v`, однако это приведёт к удалению сохранённых данных Replica Set.