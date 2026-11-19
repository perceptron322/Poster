// До/после для двух запросов MongoDB из задания по оптимизации.
const RUNS = Number(process.env.RUNS || 11);
const WARMUP = Number(process.env.WARMUP || 2);

const sample = db.event_pages.findOne({}, { 'event.type': 1, performer_ids: 1 });
if (!sample || !sample.performer_ids || sample.performer_ids.length === 0) {
  throw new Error('Нужны мероприятия со ссылками на исполнителей; проверьте event_pages');
}

const cases = [
  {
    name: 'event_catalog', collection: db.event_pages,
    filter: { 'event.type': sample.event.type },
    query: () => db.event_pages.find({ 'event.type': sample.event.type })
      .sort({ 'event.starts_at': 1 }),
    indexes: ['type_starts_at'],
    create: () => db.event_pages.createIndex(
      { 'event.type': 1, 'event.starts_at': 1 }, { name: 'type_starts_at' },
    ),
  },
  {
    name: 'performer_events', collection: db.event_pages,
    filter: { performer_ids: sample.performer_ids[0] },
    query: () => db.event_pages.find({ performer_ids: sample.performer_ids[0] })
      .sort({ 'event.starts_at': 1 }),
    indexes: ['performer_events'],
    create: () => db.event_pages.createIndex(
      { performer_ids: 1, 'event.starts_at': 1 }, { name: 'performer_events' },
    ),
  },
];

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function measure(test, phase) {
  for (let i = 0; i < WARMUP; i++) test.query().explain('executionStats');
  const sample = [];
  let plan;
  for (let i = 0; i < RUNS; i++) {
    plan = test.query().explain('executionStats');
    const s = plan.executionStats;
    sample.push({ executionTimeMillis: s.executionTimeMillis, totalDocsExamined: s.totalDocsExamined,
      totalKeysExamined: s.totalKeysExamined, returnedDocuments: s.nReturned });
  }
  print(JSON.stringify({ query: test.name, filter: test.filter, phase,
    runs: RUNS, warmupRuns: WARMUP,
    medianExecutionTimeMillis: median(sample.map((x) => x.executionTimeMillis)),
    medianTotalDocsExamined: median(sample.map((x) => x.totalDocsExamined)),
    medianTotalKeysExamined: median(sample.map((x) => x.totalKeysExamined)),
    medianReturnedDocuments: median(sample.map((x) => x.returnedDocuments)), sample,
    queryPlanner: plan.queryPlanner }));
}

// Для базового плана снимаем оба проверяемых индекса.
const baselineIndexes = cases.flatMap((test) => test.indexes.map((name) => ({
  collection: test.collection, name, create: test.create,
})));
for (const index of baselineIndexes) {
  if (index.collection.getIndexes().some((item) => item.name === index.name)) index.collection.dropIndex(index.name);
}
try {
  for (const test of cases) measure(test, 'before');

  // Создаём два целевых индекса.
  for (const test of cases) test.create();
  for (const test of cases) measure(test, 'after');
} finally {
  // Оставляем коллекции в оптимизированном состоянии, даже если замер упал.
  for (const index of baselineIndexes) {
    if (!index.collection.getIndexes().some((item) => item.name === index.name)) index.create();
  }
}
