import csv
import subprocess
import time
from pathlib import Path

data_file = Path("scripts/performance/bulk_load/data.csv")
sql_file = Path("scripts/performance/bulk_load/insert_batches.sql")
batch_size = 500

with data_file.open(newline="") as file:
    rows = list(csv.reader(file))

# Подготавливаем SQL до начала замера
with sql_file.open("w") as file:
    file.write("BEGIN;\n")

    for offset in range(0, len(rows), batch_size):
        batch = rows[offset:offset + batch_size]
        values = []

        for row in batch:
            values.append(
                f"({int(row[0])}, '{row[1]}', {row[2]}, "
                f"'{row[3]}'::timestamptz)"
            )

        file.write(
            "INSERT INTO bulk_load_benchmark "
            "(id, name, amount, created_at) VALUES "
            + ", ".join(values)
            + ";\n"
        )

    file.write("COMMIT;\n")

# Очищаем таблицу до начала замера
subprocess.run(
    [
        "docker", "compose", "exec", "-T", "db",
        "psql", "-U", "poster", "-d", "poster",
        "-v", "ON_ERROR_STOP=1",
        "-c", "TRUNCATE TABLE bulk_load_benchmark;"
    ],
    check=True,
    stdout=subprocess.DEVNULL
)

# Замеряем выполнение всех INSERT одним процессом psql
start = time.perf_counter()

with sql_file.open() as file:
    subprocess.run(
        [
            "docker", "compose", "exec", "-T", "db",
            "psql", "-U", "poster", "-d", "poster",
            "-v", "ON_ERROR_STOP=1"
        ],
        stdin=file,
        check=True,
        stdout=subprocess.DEVNULL
    )

elapsed = time.perf_counter() - start

print(
    f"INSERT batches: {len(rows)} rows, "
    f"batch size {batch_size}, "
    f"one transaction: {elapsed:.3f} seconds"
)