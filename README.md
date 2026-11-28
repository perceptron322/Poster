# [Спринт 1](docs/sprint-01.md)

# [Спринт 2](docs/sprint-02.md)

# [Спринт 3](docs/sprint-03.md)

# [Спринт 4](docs/sprint-04.md)

# [Спринт 5](docs/sprint-05.md)

# [Спринт 6](docs/sprint-06.md)

# Poster

Poster — афиша мероприятий с публикацией, покупкой и возвратом билетов. Бэкенд работает на Go и PostgreSQL. [Спецификация OpenAPI](docs/openapi.yaml) · [Архитектура и бизнес-правила](docs/architecture.md)

## Быстрый старт

Понадобятся Go 1.27, Docker Compose, Make и CLI golang-migrate с драйвером PostgreSQL. Из корня проекта выполните:

```bash
make setup
make run
```

Откройте [Swagger UI](http://localhost:8081/) в браузере. Выберите операцию и нажмите **Try it out → Execute**. Для запросов к личному кабинету сначала выполните `POST /api/v1/auth/login` прямо в Swagger UI. Контракт доступен по адресу [/openapi.yaml](http://localhost:8081/openapi.yaml).

По умолчанию API слушает на порту 8081. `make setup` создаёт или дополняет локальный `.env`, запускает PostgreSQL и применяет миграции. При обновлении уже запущенной базы выполните `make migrate`. Для сборки исполняемого файла используйте `make build`.

```bash
curl -sS http://localhost:8081/readyz
curl -sS 'http://localhost:8081/api/v1/events?type=concert&limit=5'
```

## Пример покупки и возврата

Пример рассчитан на Bash, curl и jq. На чистой базе сначала загрузите учебные площадки командой `make seed`. Пример создаёт будущее мероприятие и использует идентификаторы из ответов API.

```bash
api=http://localhost:8081/api/v1
cookies=$(mktemp)
read -rsp 'Пароль для новой учётной записи (от 8 байт): ' password
echo
jq -n --arg p "$password" '{name:"Анна",email:"demo@example.org",password:$p}' |
  curl -fsS -c "$cookies" --json @- "$api/auth/register"
unset password
```

Назначьте этому пользователю роль организатора. В `make db-shell` выполните:

```sql
UPDATE users SET role = 'organizer' WHERE email = 'demo@example.org';
```

Вернитесь в тот же Bash. Организатор может купить билет и проверить свой кабинет в одной сессии:

```bash
location=$(curl -fsS "$api/locations?limit=1" | jq -er '.[0].id')
event=$(jq -n --arg at "$(date -u -d 'tomorrow 18:00' +%FT%TZ)" --argjson loc "$location" \
  '{title:"Вечер джаза",description:"Живой концерт",cover:"https://example.org/jazz.jpg",
    starts_at:$at,duration_minutes:90,type:"concert",ticket_price:"450.00",location_id:$loc}' |
  curl -fsS -b "$cookies" --json @- "$api/events" | jq -er .id)
order=$(curl -fsS -b "$cookies" -H "Idempotency-Key: demo-$event" \
  --json "$(jq -n --argjson e "$event" '{event_id:$e, quantity:2}')" "$api/orders")
order_id=$(jq -r .id <<<"$order")
curl -fsS -b "$cookies" "$api/me/orders"
jq '{ticket_ids:[.tickets[0].id]}' <<<"$order" |
  curl -fsS -b "$cookies" --json @- "$api/me/orders/$order_id/refunds"
curl -fsS -b "$cookies" -X POST "$api/events/$event/cancel"
curl -fsS -b "$cookies" -X POST "$api/auth/logout"
rm "$cookies"
```

Для браузера направляйте запросы по относительному пути `/api/v1` через тот же origin, что и интерфейс. При завершении HTTPS на обратном прокси задайте `COOKIE_SECURE=true`. Время передаётся со смещением, цены — десятичными строками.

## Проверка

```bash
go test ./...
make test-api
```

Для `make test-api` также нужен Python 3. Сквозная проверка поднимает временный PostgreSQL 16 на отдельном порту, прогоняет миграции на чистой и ранее заполненной схеме, запускает API и проверяет права, брони, конкурентную покупку, возвраты и отмену. В конце контейнер удаляется.
