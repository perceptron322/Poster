# PostgreSQL: диагностика репликации и восстановление

## 1. Назначение

Документ описывает проверку потоковой репликации PostgreSQL, диагностику отказов, восстановление после остановки узлов и проверку резервных копий в учебном HA-стенде проекта Poster.

Стенд расположен в `scripts/ha-lab/` и использует отдельные контейнеры и тома. Основная база Poster на порту `5433` не входит в этот стенд. Не удаляйте её том `pgdata` и не используйте `docker compose down -v` для основной конфигурации.

## 2. Проверка состояния контейнеров

Из корня репозитория выполните:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env ps
```

Ожидаемое состояние после запуска — контейнеры `primary` и `replica` имеют статус `healthy`.

Если один из узлов не готов, проверьте логи:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env logs --tail=100 primary replica
```

При анализе логов обратите внимание на сообщения о готовности сервера, подключении к primary, получении WAL и переходе реплики в режим standby.

## 3. Проверка ролей узлов

Проверка primary:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env exec -T primary \
  psql -U course_admin -d course_app -c "SELECT pg_is_in_recovery();"
```

Ожидаемый результат — `false`.

Проверка replica:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env exec -T replica \
  psql -U course_admin -d course_app -c "SELECT pg_is_in_recovery();"
```

Ожидаемый результат — `true`.

Функция `pg_is_in_recovery()` возвращает `true`, если сервер находится в режиме восстановления, как физическая реплика PostgreSQL.

## 4. Проверка потоковой репликации

На primary выполните:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env exec -T primary \
  psql -U course_admin -d course_app -c \
  "SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

Ожидается подключение реплики со статусом `streaming`. В текущем стенде используется асинхронная репликация (`async`).

Если строк нет:

1. Проверьте состояние обоих контейнеров.
2. Посмотрите логи primary и replica.
3. Убедитесь, что primary принимает подключения.
4. После восстановления соединения повторите запрос.

При асинхронной репликации возможна небольшая задержка между записью на primary и появлением данных на replica.

## 5. Проверка репликации схемы и данных Poster

Для тестирования схемы приложения используется отдельная база `poster_ha`.

Проверка списка таблиц на primary:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env exec -T primary \
  psql -U course_admin -d poster_ha -c \
  "SELECT schemaname, tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;"
```

Повторите запрос на replica, заменив `primary` на `replica`.

В ходе эксперимента на обоих узлах были обнаружены таблицы:

- `users`
- `locations`
- `events`
- `orders`
- `tickets`
- `location_bookings`
- `schema_migrations`

Дополнительно проверялась запись тестового пользователя в `public.users`. Запись, созданная на primary, появилась на replica. После удаления пользователя на primary запрос на replica вернул ноль строк.

Для проверки конкретной записи используйте:

```sql
SELECT user_id, name, email, role
FROM public.users
WHERE email = 'ha-probe-20261019@example.test';
```

Этот запрос следует выполнять на каждом узле отдельно. После завершения эксперимента тестовая запись была удалена.

## 6. Остановка и восстановление replica

Остановите только реплику:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env stop replica
```

Проверьте состояние контейнеров:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env ps
```

В ходе эксперимента primary продолжал принимать записи при остановленной replica.

Запустите реплику обратно:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env start replica
```

Дождитесь состояния `healthy`, затем повторите проверку `pg_stat_replication` из раздела 4 и убедитесь, что контрольная запись доступна на replica.

В эксперименте после повторного запуска репликация возобновилась автоматически.

## 7. Остановка и восстановление primary

Остановка primary:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env stop primary
```

Проверьте состояние узлов и доступность replica. В эксперименте replica оставалась доступной для чтения, но автоматического повышения её до primary не происходило.

Запуск primary:

```bash
docker compose -f scripts/ha-lab/compose.yaml --env-file scripts/ha-lab/.env start primary
```

После запуска проверьте готовность primary, а затем состояние репликации запросом из раздела 4.

В ходе эксперимента после повторного запуска primary репликация возобновилась.

**Важно:** автоматический failover и перенаправление приложения на другой узел в текущем стенде не настроены. Не повышайте replica до primary без отдельного плана восстановления и проверки состояния данных.

## 8. Резервное копирование и восстановление

В ходе эксперимента была создана резервная копия базы `course_app` в формате custom с помощью `pg_dump`. Архив проверялся командой `pg_restore --list`, а затем восстанавливался в отдельную базу `course_app_restored`.

Проверка содержимого архива выполняется так:

```bash
pg_restore --list course_app.dump
```

При необходимости выполнения команды внутри контейнера сначала скопируйте архив в контейнер и запускайте `pg_restore --list` для скопированного файла.

Восстанавливайте архив в отдельную тестовую базу. Перед восстановлением убедитесь, что целевая база предназначена для эксперимента. Не восстанавливайте учебный архив поверх основной БД Poster.

После восстановления проверьте:

- наличие ожидаемых таблиц;
- наличие контрольных данных;
- наличие первичных ключей и уникальных ограничений;
- возможность чтения восстановленных записей.

В проверенном эксперименте восстановление завершилось успешно, а контрольные записи и ограничения таблицы `app.replication_probe` присутствовали в восстановленной базе.

## 9. Ограничения и обнаруженные проблемы

1. Репликация асинхронная. При аварии primary возможна потеря последних транзакций, которые ещё не были применены на replica.
2. Автоматический failover не настроен.
3. Доступность replica для чтения не гарантирует возможность записи.
4. SQL-проверки подтверждают работу репликации PostgreSQL, но не заменяют тестирование приложения через HTTP API.
5. В текущем коммите файлы `cmd/api/main.go`, `internal/database/db.go` и `internal/config/config.go` пустые. Поэтому полноценный тест HTTP API Poster в рамках эксперимента не проводился.
6. Основная база Poster на порту `5433` отделена от HA-стенда, использующего порт primary `55432` и порт replica `55433`.

## 10. Итог

В учебном стенде проверены потоковая репликация PostgreSQL, передача схемы и данных Poster, поведение узлов при остановке, восстановление репликации после запуска и восстановление резервной копии в отдельную базу.

Эксперименты подтвердили работу асинхронной репликации и сохранение проверенных ограничений данных. При этом стенд не обеспечивает автоматический failover и не подтверждает отказоустойчивость HTTP API приложения.