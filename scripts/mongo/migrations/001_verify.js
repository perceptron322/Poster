/** Verify the required schema version and BSON int type in all collections. */

const expectations = [
  ['event_pages', NumberInt(2)],
  ['performers', NumberInt(1)],
  ['reviews', NumberInt(1)],
];

let totalInvalid = 0;
print('=== MongoDB schema version verification ===');

for (const [name, expected] of expectations) {
  const collection = db.getCollection(name);
  const total = collection.countDocuments({});
  const valid = collection.countDocuments({
    $expr: {
      $and: [
        { $eq: [{ $type: '$schemaVersion' }, 'int'] },
        { $eq: ['$schemaVersion', expected] },
      ],
    },
  });
  const invalid = total - valid;
  totalInvalid += invalid;
  print(`${name}: total=${total}, expectedVersion=${expected}, invalid=${invalid}`);
}

if (totalInvalid === 0) {
  print('RESULT: SUCCESS');
} else {
  print(`RESULT: FAILED (${totalInvalid} invalid document(s))`);
  quit(1);
}
