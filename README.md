# [Спринт 1](docs/sprint-01.md)

# [Спринт 2](docs/sprint-02.md)

# [Спринт 3](docs/sprint-03.md)

# [Спринт 4](docs/sprint-04.md)

# [Спринт 5](docs/sprint-05.md)

# [Спринт 6](docs/sprint-06.md)

# [Спринт 7](docs/sprint-07.md)

# Poster

Poster — афиша мероприятий с публикацией, покупкой и возвратом билетов. Бэкенд работает на Go, PostgreSQL и MongoDB. [Спецификация OpenAPI](docs/openapi.yaml) · [Архитектура и бизнес-правила](docs/architecture.md)

## Быстрый старт

Понадобятся Go 1.27, Docker Compose, Make и CLI golang-migrate с драйвером PostgreSQL. Из корня проекта выполните:

```bash
make setup
make run
```

Откройте [Swagger UI](http://localhost:8081/) в браузере. Выберите операцию и нажмите **Try it out → Execute**. Для запросов к личному кабинету сначала выполните `POST /api/v1/auth/login` прямо в Swagger UI. Контракт доступен по адресу [/openapi.yaml](http://localhost:8081/openapi.yaml).

По умолчанию API слушает на порту 8081. `make setup` создаёт или дополняет локальный `.env`, запускает PostgreSQL и MongoDB, применяет SQL-миграции и создаёт коллекции MongoDB с валидаторами и индексами. При обновлении уже запущенной базы выполните `make migrate`. Для сборки исполняемого файла используйте `make build`.

```bash
curl -sS http://localhost:8081/readyz
curl -sS 'http://localhost:8081/api/v1/events?type=concert&limit=5'
```

## MongoDB и контент

В существующем проекте выполните `make mongo-start`, затем `make mongo-schema` и запустите обновлённый API через `make run`. Инициализация схемы сохраняет документы. По умолчанию API использует базу `poster_content` на `localhost:27018`. Параметры задаются через `MONGO_HOST`, `MONGO_PORT`, `MONGO_USER`, `MONGO_PASSWORD` и `MONGO_DB`. Для внешнего сервера можно задать строку соединения `MONGO_URI`. Базу для коллекций выбирает `MONGO_DB`. Для новой внешней базы примените `scripts/mongo/01_schema.js` через mongosh в этой базе.

В разделе **Контент** в Swagger выберите `PUT /api/v1/events/{id}/page`, чтобы создать страницу своего предстоящего мероприятия. Для концерта на пустой MongoDB подойдёт следующий запрос:

```json
{"summary":"Вечер джаза","details":{"genre":"jazz","age_limit":0},"program":[],"performer_ids":[],"gallery":[]}
```

Страница доступна гостю через `GET /api/v1/events/{id}/page`, справочник исполнителей — через `GET /api/v1/performers`. После окончания мероприятия покупатель с оплаченным заказом может оставить отзыв через `POST /api/v1/events/{id}/reviews` с телом `{"rating":5,"text":"Отличный концерт"}`. Лента отзывов доступна по тому же пути методом GET.

Учебная команда `make mongo-seed` **заменяет документы во всех трёх коллекциях** демонстрационными данными на основе событий PostgreSQL. Для обычного запуска и публикации страницы достаточно `make setup`.

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

Для `make test-api` также нужен Python 3. Сквозная проверка поднимает временные PostgreSQL 16 и MongoDB 7 на отдельных портах, прогоняет миграции на чистой и ранее заполненной схеме, запускает API и проверяет права, брони, конкурентную покупку, возвраты, контент, отзывы и отключение каждой базы. В конце контейнеры удаляются.
