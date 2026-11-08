// Встроенные массивы ограничены, страницы далеко от лимита документа 16 МБ.
const BUDGET = 64 * 1024; // бюджет на одну страницу мероприятия
const s = db.event_pages.aggregate([{ $group: {
  _id: null,
  maxBytes: { $max: { $bsonSize: '$$ROOT' } },
  maxProgram: { $max: { $size: '$program' } },
  maxPerformers: { $max: { $size: '$performer_ids' } },
} }]).next();
print(`  max bsonSize=${s.maxBytes} Б (бюджет ${BUDGET}), max program=${s.maxProgram}, max performer_ids=${s.maxPerformers}`);
if (s.maxBytes > BUDGET) throw new Error('страница превысила бюджет размера');
if (s.maxProgram > 50 || s.maxPerformers > 30) throw new Error('встроенный массив превысил границу');
