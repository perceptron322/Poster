/**
 * Migration: event_pages V1 -> V2
 *
 * V1:
 * {
 *   summary: "Описание мероприятия"
 * }
 *
 * V2:
 * {
 *   schemaVersion: 2,
 *   content: {
 *     summary: "Описание мероприятия"
 *   }
 * }
 *
 * Documents without schemaVersion are treated as V1.
 *
 * Migration is:
 * - safe to rerun;
 * - atomic for each individual document;
 * - protected against concurrent modifications.
 */

const collection = db.getCollection('event_pages');

const filter = {
  $or: [
    { schemaVersion: { $exists: false } },
    { schemaVersion: NumberInt(1) },
  ],
};

let migrated = 0;
let skipped = 0;
let conflicts = 0;

print('Starting event_pages migration V1 -> V2');

collection.find(filter).sort({ _id: 1 }).forEach((doc) => {
  // V1 document must not already contain content.
  if (doc.content !== undefined) {
    print(`ERROR: unexpected content in V1 document ${doc._id}`);
    skipped++;
    return;
  }

  // Move summary into content, preserving its value.
  const content = {};

  if (Object.prototype.hasOwnProperty.call(doc, 'summary')) {
    if (typeof doc.summary !== 'string') {
      print(`ERROR: invalid summary in document ${doc._id}`);
      skipped++;
      return;
    }

    content.summary = doc.summary;
  }

  // Optimistic concurrency protection.
  const versionFilter = doc.schemaVersion === undefined
    ? { schemaVersion: { $exists: false } }
    : { schemaVersion: NumberInt(1) };

  const summaryFilter = Object.prototype.hasOwnProperty.call(doc, 'summary')
    ? { summary: doc.summary }
    : { summary: { $exists: false } };

  const result = collection.updateOne(
    {
      _id: doc._id,
      ...versionFilter,
      ...summaryFilter,
      content: { $exists: false },
    },
    {
      $set: {
        schemaVersion: NumberInt(2),
        content,
      },
      $unset: {
        summary: '',
      },
    },
  );

  if (result.modifiedCount === 1) {
    migrated++;
    print(`Migrated document: ${doc._id}`);
  } else {
    conflicts++;
    print(`CONFLICT: document ${doc._id} was changed`);
  }
});

print('Migration finished');
print(`Migrated: ${migrated}`);
print(`Skipped: ${skipped}`);
print(`Conflicts: ${conflicts}`);