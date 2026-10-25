## Секреты

- Реальные значения паролей и ключей хранятся только в `.env`, который в `.gitignore`
  (там же `*.key`, `*.pem`, `*.crt`, `.pgpass`, `secrets/`).
  В репозитории лежит лишь шаблон `.env.example` с заглушками `change_me*`.
- `make env` (и `make ha-lab-env` для `scripts/ha-lab`) создаёт `.env` с правами `600`
  или дописывает в него недостающие переменные; каждая заглушка заменяется
  своим случайным значением (`openssl rand -hex 16`), уже заданные значения не меняются.
- Makefile читает только `.env`, заглушки из шаблона не подставляются: без нужной
  переменной `migrate` и `create-roles` падают с понятной ошибкой.
- Пароль `secret`, который был в ранних коммитах (`.env.example`, `seed/config*.json`,
  `Makefile`, `README`), считается скомпрометированным и нигде не используется.
  Эти коммиты перечислены в `.gitleaksignore`, историю не переписываем.
- В CI секреты берутся из GitHub → Settings → Secrets and variables → Actions,
  на сервере — из `.env` с правами `600` или Docker secrets.
- Перед коммитом проверка `gitleaks` (`make secrets-scan`, pre-commit хук, CI).
- Если секрет попал в git — сначала сменить его, потом уже чистить историю.

## Резервное копирование и восстановление

Логический бэкап (`pg_dump`) базы `poster` и восстановление в отдельный чистый экземпляр
PostgreSQL 16 (сервис `restore` в `docker-compose.yml`, профиль `restore`, порт `5435`).

```bash
make backup                 # роли + база -> backups/poster_<дата>.{roles.sql,dump,sha256}
make restore                # самый свежий бэкап -> чистый экземпляр + сверка с исходной БД
make restore file=backups/poster_20261019_235104.dump   # конкретный бэкап
make restore-down           # удалить экземпляр восстановления
```

Что делают скрипты (`scripts/backup/`):

1. `backup.sh` — `pg_dumpall --roles-only` (роли с хешами паролей: без них не восстановятся
   права `GRANT`) и `pg_dump -Fc`; файлы пишутся через `.tmp`, чтобы при сбое не остался
   обрезанный бэкап; считаются `sha256`; архив проверяется `pg_restore --list`.
2. `restore.sh` — проверяет контрольные суммы, пересоздаёт контейнер `restore` с пустым
   томом и убеждается, что базы `poster` в нём нет; восстанавливает роли, затем базу
   (`pg_restore -C --exit-on-error`).
3. `compare.sql` выполняется на исходной и восстановленной БД, результаты сравниваются `diff`:
   число строк и md5 содержимого каждой таблицы, ограничения, индексы, расширения,
   значения последовательностей, роли и права на таблицы.

Бэкапы содержат персональные данные и хеши паролей: `backups/` в `.gitignore`,
файлы создаются с правами `600`.

### Результат проверки

Исходная БД заполнена генератором `scripts/seed` (`make -C scripts/seed run`) и ролями
(`make create-roles`). Бэкап — 932 КБ, 255 объектов в оглавлении; восстановление — около 7 с.

| Таблица | Строк |
|---|---:|
| events | 502 |
| location_bookings | 457 |
| locations | 22 |
| orders | 29 754 |
| schema_migrations | 1 |
| tickets | 89 048 |
| users | 1 003 |

- `compare.sql` на обеих БД совпал полностью: данные (md5), 29 ограничений, индексы,
  расширение `btree_gist`, последовательности, роли `admin_user`/`app_user`/`analyst_user`, права.
- `app_user` входит в восстановленную БД по TCP со своим паролем из `.env`;
  `analyst_user` получает `permission denied` на `DELETE`; CHECK `events_status_check` отклоняет
  недопустимый статус.
- Контроль самой сверки: после удаления одной строки из `tickets` в копии `diff` показал
  расхождение по числу строк и md5.

Нюанс: текст CHECK-ограничений вида `IN (...)` после `pg_restore` отличается расстановкой
приведений типов (`ARRAY[...]::text[]` → `ARRAY[(...)::text, ...]`) при том же смысле,
поэтому `compare.sql` сравнивает определения ограничений без приведений типов и скобок.


###RLS Test
Добавлен скрипт test_rls.sh, который автоматически создает таблицу, включает RLS-политику и доказывает, что пользователи alice и bob видят только свои данные.

cp .env.example .env

mkdir -p ./archive
sudo chown -R 999:999 ./archive
sudo chmod 700 ./archive

docker compose up -d

chmod +x ./scripts/postgres/test_rls.sh
./scripts/postgres/test_rls.sh

## Репликация: тестовый HA-стенд

Учебный стенд `scripts/ha-lab/`: primary (`127.0.0.1:55432`) и replica (`127.0.0.1:55433`). Тома и сеть у стенда свои, основную БД Poster на порту `5433` команды не трогают.
Подробная диагностика отказов описана в `docs/runbooks/postgresql-replication.md`.

Все команды запускаются из корня репозитория и вызывают `scripts/ha-lab/ha.sh`.
Если `scripts/ha-lab/.env` ещё нет, скрипт создаёт его из `.env.example` со случайными
паролями (как `make ha-lab-env`). Переменные стенда перекрывают переменные корневого `.env`,
иначе `POSTGRES_DB=poster` из него подменил бы `course_app`.

| Команда | Что делает |
|---|---|
| `make ha-up` | Поднимает primary и replica, ждёт `healthy` и состояния `streaming` в `pg_stat_replication`. При первом запуске replica создаётся через `pg_basebackup` |
| `make ha-status` | Проверка репликации: `01-primary-status.sql` на primary (`pg_is_in_recovery() = f`, `pg_stat_replication`) и `03-replica-status.sql` на replica (`pg_is_in_recovery() = t`, `pg_stat_wal_receiver`) |
| `make ha-lsn` | LSN: на primary — `pg_current_wal_lsn()`, `sent/write/flush/replay_lsn`, отставание `replay_lag_bytes` и `replay_lag`; на replica — `receive_lsn`, `replay_lsn`, неприменённые байты и время последней применённой транзакции |
| `make ha-restart` | Перезапускает replica, ждёт возобновления `streaming` и показывает LSN |
| `make ha-rebuild` | Пересоздаёт replica с нуля: удаляет контейнер и том `sprint04_replica_data`, делает новый `pg_basebackup`. Нужен, если реплика отстала и WAL на primary уже удалены (`wal_keep_size=256MB`) |
| `make ha-test` | Автотесты репликации, при ошибке завершается с кодом 1 |
| `make ha-logs` | Последние 100 строк логов primary и replica |
| `make ha-down` | Останавливает стенд, тома с данными сохраняются |
| `make ha-clean` | Останавливает стенд (вместе с узлом `restore`) и удаляет его тома |

Что проверяет `make ha-test`:

1. Роли узлов: primary не в recovery, replica в recovery (hot standby).
2. `course_replica` в `pg_stat_replication` в состоянии `streaming/async`.
3. Запись в `app.replication_probe` на primary появляется на replica: тест ждёт, пока
   `pg_last_wal_replay_lsn()` реплики дойдёт до LSN после `INSERT`, и ищет запись по маркеру.
4. `INSERT` на replica отклоняется с ошибкой `read-only transaction`.
5. Число строк, максимальный `id` и md5 маркеров `app.replication_probe` на узлах совпадают,
   дубликатов маркеров нет.

Типичный прогон:

```bash
make ha-up        # поднять стенд
make ha-test      # убедиться, что репликация работает
make ha-lsn       # посмотреть LSN и отставание
make ha-restart   # перезапустить реплику, затем снова make ha-test
make ha-down      # остановить стенд
```
