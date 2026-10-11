import csv
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

count = 50000
output = Path("scripts/performance/bulk_load/data.csv")
start = datetime(2026, 1, 1, tzinfo=timezone.utc)

with output.open("w", newline="") as file:
    writer = csv.writer(file)

    for i in range(1, count + 1):
        writer.writerow([
            i,
            f"user_{i}",
            Decimal(i % 100000) / 100,
            (start + timedelta(seconds=i)).isoformat()
        ])

print(f"Generated {count} rows: {output}")
