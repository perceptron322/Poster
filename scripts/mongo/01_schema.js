// Схема документной модели Poster: три коллекции, валидаторы $jsonSchema и индексы.
// Идемпотентно: существующая коллекция получает новый валидатор через collMod.
//
//   event_pages  — контент страницы мероприятия. _id = events.event_id из PostgreSQL.
//                  ВСТРАИВАНИЕ: program[] (программа) и details (поля, зависящие от типа).
//                  ССЫЛКА M:N: performer_ids[] → performers._id.
//   performers   — исполнители / спикеры / труппы, общие для многих событий.
//   reviews      — отзывы. ССЫЛКА 1:N: reviews.event_id → event_pages._id.

const MAX_PROGRAM_ITEMS = 50;   // граница встраивания: программа ограничена по размеру
const MAX_GALLERY_ITEMS = 20;
const MAX_PERFORMERS = 30;

const date = { bsonType: 'date' };
const str = (maxLength) => ({ bsonType: 'string', minLength: 1, maxLength });
const url = { bsonType: 'string', pattern: '^https://' };

// Дискриминатор event.type → обязательная форма details.
// Эти поля есть только у своего типа: в PostgreSQL это были бы
// пять nullable-колонок или EAV-таблица.
const detailsByType = {
  concert: {
    required: ['genre', 'age_limit'],
    properties: {
      genre: str(50),
      age_limit: { bsonType: 'int', enum: [0, 6, 12, 16, 18] },
      setlist_public: { bsonType: 'bool' },
    },
  },
  lecture: {
    required: ['topic', 'level'],
    properties: {
      topic: str(100),
      level: { enum: ['beginner', 'intermediate', 'advanced'] },
      materials: { bsonType: 'array', maxItems: 10, items: url },
    },
  },
  theatre: {
    required: ['troupe_id', 'acts', 'age_limit'],
    properties: {
      troupe_id: str(20),
      acts: { bsonType: 'int', minimum: 1, maximum: 5 },
      age_limit: { bsonType: 'int', enum: [0, 6, 12, 16, 18] },
    },
  },
  festival: {
    required: ['stages'],
    properties: {
      stages: {
        bsonType: 'array', minItems: 1, maxItems: 10,
        items: {
          bsonType: 'object', required: ['name', 'genre'], additionalProperties: false,
          properties: { name: str(50), genre: str(50) },
        },
      },
    },
  },
  other: {
    properties: { note: str(500) },
  },
};

const eventPagesSchema = {
  bsonType: 'object',
  required: ['_id', 'event', 'details', 'program', 'performer_ids', 'rating', 'synced_at', 'updated_at'],
  properties: {
    _id: { bsonType: 'int', minimum: 1 },               // = events.event_id в PostgreSQL
    // Снимок полей из PostgreSQL. Источник истины — PG, здесь копия для одного чтения.
    event: {
      bsonType: 'object',
      required: ['title', 'type', 'status', 'starts_at', 'ends_at'],
      additionalProperties: false,
      properties: {
        title: str(300),
        type: { enum: Object.keys(detailsByType) },
        status: { enum: ['published', 'cancelled', 'finished'] },
        starts_at: date,
        ends_at: date,
      },
    },
    synced_at: date,
    summary: str(2000),
    details: { bsonType: 'object' },
    program: {
      bsonType: 'array', maxItems: MAX_PROGRAM_ITEMS,
      items: {
        bsonType: 'object', required: ['starts_at', 'title'], additionalProperties: false,
        properties: {
          starts_at: date,
          title: str(200),
          performer_id: str(20),
          stage: str(50),
        },
      },
    },
    performer_ids: { bsonType: 'array', maxItems: MAX_PERFORMERS, uniqueItems: true, items: str(20) },
    gallery: { bsonType: 'array', maxItems: MAX_GALLERY_ITEMS, items: url },
    // Кэш агрегата по reviews. Источник истины — коллекция reviews.
    rating: {
      bsonType: 'object', required: ['count', 'avg'], additionalProperties: false,
      properties: {
        count: { bsonType: 'int', minimum: 0 },
        avg: { bsonType: ['double', 'int', 'null'], minimum: 1, maximum: 5 },
      },
    },
    updated_at: date,
  },
  // Полиморфизм: форма details определяется event.type.
  oneOf: Object.entries(detailsByType).map(([type, d]) => ({
    properties: {
      event: { properties: { type: { enum: [type] } } },
      details: { bsonType: 'object', additionalProperties: false, ...d },
    },
  })),
};

const performersSchema = {
  bsonType: 'object',
  required: ['_id', 'name', 'kind', 'updated_at'],
  additionalProperties: false,
  properties: {
    _id: { bsonType: 'string', pattern: '^(perf|troupe)-[0-9]{4}$' },
    name: str(200),
    kind: { enum: ['musician', 'band', 'dj', 'speaker', 'troupe', 'host'] },
    bio: str(5000),
    genres: { bsonType: 'array', maxItems: 10, items: str(50) },
    links: {
      bsonType: 'object', additionalProperties: false,
      properties: { site: url, socials: { bsonType: 'array', maxItems: 10, items: url } },
    },
    photo: url,
    updated_at: date,
  },
};

const reviewsSchema = {
  bsonType: 'object',
  required: ['_id', 'event_id', 'user_id', 'rating', 'created_at'],
  additionalProperties: false,
  properties: {
    _id: { bsonType: 'objectId' },
    event_id: { bsonType: 'int', minimum: 1 },          // → event_pages._id (= events.event_id)
    user_id: { bsonType: 'int', minimum: 1 },           // → users.user_id в PostgreSQL
    rating: { bsonType: 'int', minimum: 1, maximum: 5 },
    text: { bsonType: 'string', maxLength: 4000 },
    helpful_votes: { bsonType: 'int', minimum: 0 },
    created_at: date,
  },
};

function ensureCollection(name, schema) {
  const opts = { validator: { $jsonSchema: schema }, validationLevel: 'strict', validationAction: 'error' };
  if (db.getCollectionNames().includes(name)) {
    db.runCommand({ collMod: name, ...opts });
    print(`collMod  ${name}`);
  } else {
    db.createCollection(name, opts);
    print(`create   ${name}`);
  }
}

ensureCollection('event_pages', eventPagesSchema);
ensureCollection('performers', performersSchema);
ensureCollection('reviews', reviewsSchema);

// event_pages: каталог по типу и дате; обратный обход M:N «исполнитель → события» (multikey).
db.event_pages.createIndex({ 'event.type': 1, 'event.starts_at': 1 }, { name: 'type_starts_at' });
db.event_pages.createIndex({ performer_ids: 1, 'event.starts_at': 1 }, { name: 'performer_events' });
// Поиск по полям конкретного типа: частичные индексы только по своим документам.
db.event_pages.createIndex(
  { 'details.topic': 1, 'details.level': 1 },
  { name: 'lecture_topic_level', partialFilterExpression: { 'event.type': 'lecture' } },
);
db.event_pages.createIndex(
  { 'details.stages.genre': 1 },
  { name: 'festival_stage_genre', partialFilterExpression: { 'event.type': 'festival' } },
);

db.performers.createIndex({ kind: 1, name: 1 }, { name: 'kind_name' });

// reviews: один отзыв от пользователя на событие; постраничная выдача по событию.
db.reviews.createIndex({ event_id: 1, user_id: 1 }, { name: 'one_review_per_user', unique: true });
db.reviews.createIndex({ event_id: 1, created_at: -1, _id: -1 }, { name: 'event_feed' });
db.reviews.createIndex({ user_id: 1, created_at: -1 }, { name: 'user_reviews' });

for (const c of ['event_pages', 'performers', 'reviews']) {
  print(`indexes  ${c}: ${db[c].getIndexes().map((i) => i.name).join(', ')}`);
}
