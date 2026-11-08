/**
 * Add schemaVersion: NumberInt(1) to legacy performers and reviews.
 *
 * Only schemaVersion is written. The full document snapshot is compared
 * atomically in the update filter to avoid changing concurrently edited data.
 * Existing version 1 documents are skipped; unexpected versions are conflicts.
 */

const targets = ['performers', 'reviews'];
let migrated = 0;
let skipped = 0;
let conflicts = 0;

for (const name of targets) {
  const collection = db.getCollection(name);
  print(`Starting ${name} schemaVersion migration`);

  collection.find({}).sort({ _id: 1 }).forEach((doc) => {
    if (doc.schemaVersion !== undefined) {
      const isCorrectVersion = collection.countDocuments({
        _id: doc._id,
        $expr: {
          $and: [
            { $eq: [{ $type: '$schemaVersion' }, 'int'] },
            { $eq: ['$schemaVersion', NumberInt(1)] },
          ],
        },
      }) === 1;

      if (isCorrectVersion) {
        skipped++;
      } else {
        conflicts++;
        print(`CONFLICT: unexpected schemaVersion in ${name} document ${doc._id}`);
      }
      return;
    }

    const result = collection.updateOne(
      {
        _id: doc._id,
        schemaVersion: { $exists: false },
        $expr: { $eq: ['$$ROOT', { $literal: doc }] },
      },
      { $set: { schemaVersion: NumberInt(1) } },
    );

    if (result.modifiedCount === 1) {
      migrated++;
    } else {
      conflicts++;
      print(`CONFLICT: ${name} document ${doc._id} changed during migration`);
    }
  });
}

print('Migration finished');
print(`Migrated: ${migrated}`);
print(`Skipped: ${skipped}`);
print(`Conflicts: ${conflicts}`);

if (conflicts > 0) {
  quit(1);
}
