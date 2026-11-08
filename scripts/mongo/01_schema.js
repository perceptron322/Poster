
/**
 * Схема документной модели Poster.
 *
 * Коллекции:
 * - event_pages: страницы мероприятий;
 * - performers: исполнители, спикеры и труппы;
 * - reviews: отзывы.
 *
 * Источник истины для событий — PostgreSQL.
 *
 * Версионирование event_pages:
 * - Legacy V1: без schemaVersion и content;
 * - V1: schemaVersion = 1;
 * - V2: schemaVersion = 2, описание находится в content.
 *
 * Существующие коллекции обновляются через collMod.
 */

// --------------------------------------------------
// CONSTANTS
// --------------------------------------------------

const MAX_PROGRAM_ITEMS = 50;
const MAX_GALLERY_ITEMS = 20;
const MAX_PERFORMERS = 30;

const date = {
  bsonType: 'date',
};

const str = (maxLength) => ({
  bsonType: 'string',
  minLength: 1,
  maxLength,
});

const url = {
  bsonType: 'string',
  pattern: '^https://',
};

// --------------------------------------------------
// EVENT DETAILS BY TYPE
// --------------------------------------------------

const detailsByType = {
  concert: {
    required: ['genre', 'age_limit'],
    properties: {
      genre: str(50),
      age_limit: {
        bsonType: 'int',
        enum: [0, 6, 12, 16, 18],
      },
      setlist_public: {
        bsonType: 'bool',
      },
    },
  },

  lecture: {
    required: ['topic', 'level'],
    properties: {
      topic: str(100),
      level: {
        enum: ['beginner', 'intermediate', 'advanced'],
      },
      materials: {
        bsonType: 'array',
        maxItems: 10,
        items: url,
      },
    },
  },

  theatre: {
    required: ['troupe_id', 'acts', 'age_limit'],
    properties: {
      troupe_id: str(20),
      acts: {
        bsonType: 'int',
        minimum: 1,
        maximum: 5,
      },
      age_limit: {
        bsonType: 'int',
        enum: [0, 6, 12, 16, 18],
      },
    },
  },

  festival: {
    required: ['stages'],
    properties: {
      stages: {
        bsonType: 'array',
        minItems: 1,
        maxItems: 10,
        items: {
          bsonType: 'object',
          required: ['name', 'genre'],
          additionalProperties: false,
          properties: {
            name: str(50),
            genre: str(50),
          },
        },
      },
    },
  },

  other: {
    properties: {
      note: str(500),
    },
  },
};

// --------------------------------------------------
// EVENT PAGES SCHEMA
// --------------------------------------------------

const eventPagesSchema = {
  bsonType: 'object',

  required: [
    '_id',
    'event',
    'details',
    'program',
    'performer_ids',
    'rating',
    'synced_at',
    'updated_at',
  ],

  properties: {
    _id: {
      bsonType: 'int',
      minimum: 1,
    },

    // Снимок данных из PostgreSQL.
    event: {
      bsonType: 'object',
      required: [
        'title',
        'type',
        'status',
        'starts_at',
        'ends_at',
      ],
      additionalProperties: false,
      properties: {
        title: str(300),

        type: {
          enum: Object.keys(detailsByType),
        },

        status: {
          enum: ['published', 'cancelled', 'finished'],
        },

        starts_at: date,
        ends_at: date,
      },
    },

    synced_at: date,

    // Версия схемы документа.
    // Поле отсутствует у старых документов V1.
    schemaVersion: {
      bsonType: 'int',
      enum: [1, 2],
    },

    // V1: старое расположение описания.
    summary: str(2000),

    // V2: новое расположение описания.
    content: {
      bsonType: 'object',
      additionalProperties: false,
      properties: {
        summary: str(2000),
      },
    },

    details: {
      bsonType: 'object',
    },

    program: {
      bsonType: 'array',
      maxItems: MAX_PROGRAM_ITEMS,
      items: {
        bsonType: 'object',
        required: ['starts_at', 'title'],
        additionalProperties: false,
        properties: {
          starts_at: date,
          title: str(200),
          performer_id: str(20),
          stage: str(50),
        },
      },
    },

    performer_ids: {
      bsonType: 'array',
      maxItems: MAX_PERFORMERS,
      uniqueItems: true,
      items: str(20),
    },

    gallery: {
      bsonType: 'array',
      maxItems: MAX_GALLERY_ITEMS,
      items: url,
    },

    // Кэш агрегата по коллекции reviews.
    rating: {
      bsonType: 'object',
      required: ['count', 'avg'],
      additionalProperties: false,
      properties: {
        count: {
          bsonType: 'int',
          minimum: 0,
        },
        avg: {
          bsonType: ['double', 'int', 'null'],
          minimum: 1,
          maximum: 5,
        },
      },
    },

    updated_at: date,
  },

  // Проверка версии документа.
  allOf: [
    {
      oneOf: [
        // Legacy V1:
        // schemaVersion и content отсутствуют.
        {
          not: {
            anyOf: [
              { required: ['schemaVersion'] },
              { required: ['content'] },
            ],
          },
        },

        // Явная V1:
        // schemaVersion = 1, content отсутствует.
        {
          required: ['schemaVersion'],
          properties: {
            schemaVersion: {
              bsonType: 'int',
              enum: [1],
            },
          },
          not: {
            required: ['content'],
          },
        },

        // V2:
        // schemaVersion = 2, content присутствует,
        // корневого summary быть не должно.
        {
          required: ['schemaVersion', 'content'],
          properties: {
            schemaVersion: {
              bsonType: 'int',
              enum: [2],
            },
            content: {
              bsonType: 'object',
            },
          },
          not: {
            required: ['summary'],
          },
        },
      ],
    },
  ],

  // Полиморфизм: форма details зависит от event.type.
  oneOf: Object.entries(detailsByType).map(([type, detailsSchema]) => ({
    properties: {
      event: {
        properties: {
          type: {
            enum: [type],
          },
        },
      },

      details: {
        bsonType: 'object',
        additionalProperties: false,
        ...detailsSchema,
      },
    },
  })),
};

// --------------------------------------------------
// PERFORMERS SCHEMA
// --------------------------------------------------

const performersSchema = {
  bsonType: 'object',

  required: [
    '_id',
    'name',
    'kind',
    'schemaVersion',
    'updated_at',
  ],

  additionalProperties: false,

  properties: {
    schemaVersion: {
      bsonType: 'int',
      enum: [1],
    },

    _id: {
      bsonType: 'string',
      pattern: '^(perf|troupe)-[0-9]{4}$',
    },

    name: str(200),

    kind: {
      enum: [
        'musician',
        'band',
        'dj',
        'speaker',
        'troupe',
        'host',
      ],
    },

    bio: str(5000),

    genres: {
      bsonType: 'array',
      maxItems: 10,
      items: str(50),
    },

    links: {
      bsonType: 'object',
      additionalProperties: false,
      properties: {
        site: url,

        socials: {
          bsonType: 'array',
          maxItems: 10,
          items: url,
        },
      },
    },

    photo: url,
    updated_at: date,
  },
};

// --------------------------------------------------
// REVIEWS SCHEMA
// --------------------------------------------------

const reviewsSchema = {
  bsonType: 'object',

  required: [
    '_id',
    'event_id',
    'user_id',
    'rating',
    'schemaVersion',
    'created_at',
  ],

  additionalProperties: false,

  properties: {
    schemaVersion: {
      bsonType: 'int',
      enum: [1],
    },

    _id: {
      bsonType: 'objectId',
    },

    event_id: {
      bsonType: 'int',
      minimum: 1,
    },

    user_id: {
      bsonType: 'int',
      minimum: 1,
    },

    rating: {
      bsonType: 'int',
      minimum: 1,
      maximum: 5,
    },

    text: {
      bsonType: 'string',
      maxLength: 4000,
    },

    helpful_votes: {
      bsonType: 'int',
      minimum: 0,
    },

    created_at: date,
  },
};

// --------------------------------------------------
// COLLECTION VALIDATORS
// --------------------------------------------------

function ensureCollection(name, schema) {
  const options = {
    validator: {
      $jsonSchema: schema,
    },
    validationLevel: 'strict',
    validationAction: 'error',
  };

  if (db.getCollectionNames().includes(name)) {
    const result = db.runCommand({
      collMod: name,
      ...options,
    });

    if (!result.ok) {
      throw new Error(`Failed to update validator for ${name}`);
    }

    print(`collMod  ${name}`);
  } else {
    db.createCollection(name, options);

    print(`create   ${name}`);
  }
}

ensureCollection('event_pages', eventPagesSchema);
ensureCollection('performers', performersSchema);
ensureCollection('reviews', reviewsSchema);

// --------------------------------------------------
// INDEXES
// --------------------------------------------------

// Каталог мероприятий по типу и дате.
db.event_pages.createIndex(
  {
    'event.type': 1,
    'event.starts_at': 1,
  },
  {
    name: 'type_starts_at',
  },
);

// Обратный обход M:N: исполнитель -> мероприятия.
db.event_pages.createIndex(
  {
    performer_ids: 1,
    'event.starts_at': 1,
  },
  {
    name: 'performer_events',
  },
);

// Индекс для поиска лекций.
db.event_pages.createIndex(
  {
    'details.topic': 1,
    'details.level': 1,
  },
  {
    name: 'lecture_topic_level',
    partialFilterExpression: {
      'event.type': 'lecture',
    },
  },
);

// Индекс для поиска фестивалей.
db.event_pages.createIndex(
  {
    'details.stages.genre': 1,
  },
  {
    name: 'festival_stage_genre',
    partialFilterExpression: {
      'event.type': 'festival',
    },
  },
);

// Индекс исполнителей.
db.performers.createIndex(
  {
    kind: 1,
    name: 1,
  },
  {
    name: 'kind_name',
  },
);

// Один отзыв от пользователя на одно мероприятие.
db.reviews.createIndex(
  {
    event_id: 1,
    user_id: 1,
  },
  {
    name: 'one_review_per_user',
    unique: true,
  },
);

// Постраничная выдача отзывов по мероприятию.
db.reviews.createIndex(
  {
    event_id: 1,
    created_at: -1,
    _id: -1,
  },
  {
    name: 'event_feed',
  },
);

// Отзывы конкретного пользователя.
db.reviews.createIndex(
  {
    user_id: 1,
    created_at: -1,
  },
  {
    name: 'user_reviews',
  },
);

// --------------------------------------------------
// INDEX SUMMARY
// --------------------------------------------------

for (const collectionName of [
  'event_pages',
  'performers',
  'reviews',
]) {
  print(
    `indexes ${collectionName}: ${
      db[collectionName]
        .getIndexes()
        .map((index) => index.name)
        .join(', ')
    }`,
  );
}
