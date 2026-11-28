"""Black-box checks. PostgreSQL 16 and MongoDB 7 run in disposable containers."""
import concurrent.futures
import contextlib
import datetime as dt
import http.cookiejar
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, text=True, **kwargs)


class Client:
    def __init__(self, base):
        self.base = base
        self.cookies = http.cookiejar.CookieJar()
        self.http = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))

    def call(self, method, path, status=200, body=None, headers=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers={"Content-Type": "application/json", **(headers or {})})
        try:
            response = self.http.open(req, timeout=8)
        except urllib.error.HTTPError as err:
            response = err
        with response:
            raw = response.read()
            assert response.status == status, (method, path, response.status, raw, status)
            value = json.loads(raw) if raw else None
            if status >= 400:
                assert "code" in value and "message" in value, value
            return value


def wait_for(probe):
    for _ in range(100):
        try:
            if probe():
                return
        except (urllib.error.URLError, AssertionError):
            pass
        time.sleep(0.15)
    raise RuntimeError("Сервис не перешёл в ожидаемое состояние")


def exercise(base, sql, mongo):
    with urllib.request.urlopen(base + "/", timeout=5) as response:
        assert response.url == base + "/swagger/"
        assert b"SwaggerUIBundle(" in response.read()
    with urllib.request.urlopen(base + "/openapi.yaml", timeout=5) as response:
        assert response.headers.get_content_type() == "application/yaml"
        assert response.read() == (ROOT / "docs/openapi.yaml").read_bytes()
    guest = Client(base)
    api = "/api/v1"
    events, orders = api + "/events", api + "/orders"
    cabinet = api + "/me/orders"
    organizer, buyer, other = (Client(base) for _ in range(3))
    password = secrets.token_urlsafe(18)
    for i, client in enumerate([organizer, buyer, other]):
        u = client.call("POST", api + "/auth/register", 201,
                        {"name": "Участник", "email": f"user{i}@example.org", "password": password})
        assert u["role"] == "customer" and client.call("GET", api + "/me") == u
    buyer.call("POST", api + "/auth/register", 409,
               {"name": "Дубль", "email": "USER1@example.org", "password": password})
    cookie = next(iter(buyer.cookies))
    assert cookie.has_nonstandard_attr("HttpOnly") and cookie.get_nonstandard_attr("SameSite") == "Strict"
    buyer.call("POST", api + "/auth/logout", 204)
    guest.call("GET", api + "/me", 401, headers={"Cookie": f"{cookie.name}={cookie.value}"})
    buyer.call("GET", api + "/me", 401)
    buyer.call("POST", api + "/auth/login", 401, {"email": "user1@example.org", "password": "incorrect"})
    buyer.call("POST", api + "/auth/login", 200, {"email": "USER1@example.org", "password": password})
    guest.call("POST", orders, 401, {"event_id": 1, "quantity": 1})
    other.call("POST", events, 403, {})
    other.call("POST", api + "/auth/logout", 403, headers={"Origin": "https://foreign.example"})
    sql("UPDATE users SET role='organizer' WHERE email IN ('user0@example.org','user2@example.org')")
    sql("INSERT INTO locations(name,address,capacity) VALUES ('Зал','Центр',3),('Сцена','Парк',1)")
    locations = guest.call("GET", api + "/locations")
    hall, stage = (place["id"] for place in locations)
    assert guest.call("GET", api + "/locations?limit=1&offset=1") == [locations[1]]
    start = dt.datetime.now(dt.timezone.utc).replace(microsecond=0) + dt.timedelta(days=2)
    next_day = start + dt.timedelta(days=1)
    body = {"title": "Concert Alpha 100%", "description": "Программа", "cover": "https://example.org/a.jpg",
            "starts_at": start.isoformat(), "duration_minutes": 90, "type": "concert",
            "ticket_price": "10.95", "location_id": hall}
    organizer.call("POST", events, 400, {**body, "ticket_price": "0"})
    organizer.call("POST", events, 400, {**body, "starts_at": "2000-01-01T00:00:00Z"})
    first = organizer.call("POST", events, 201, body)
    eid = first["id"]
    path = f"{events}/{eid}"
    assert first["available"] == 3
    page = path + "/page"
    content = {"summary": "Живая музыка", "details": {"genre": "jazz", "age_limit": 6},
               "program": [], "performer_ids": ["perf-0001"], "gallery": []}
    mongo("db.performers.insertOne({_id:'perf-0001',name:'Анна',kind:'musician',schemaVersion:Int32(1),updated_at:new Date()})")
    assert guest.call("GET", api + "/performers")[0]["name"] == "Анна"
    guest.call("GET", page, 404)
    guest.call("PUT", page, 401, content)
    other.call("PUT", page, 403, content)
    organizer.call("PUT", page, 400, {**content, "performer_ids": ["unknown"]})
    organizer.call("PUT", page, 400, {**content, "details": {"topic": "wrong type"}})
    published = organizer.call("PUT", page, 200, content)
    assert published["details"] == content["details"] and published["rating"] == {"count": 0, "avg": None}
    for version in ("{}", "{schemaVersion:Int32(1)}"):
        mongo(f"db.event_pages.updateOne({{_id:{eid}}},[{{$unset:['schemaVersion','content']}},{{$set:{{summary:'V1'}}}},{{$set:{version}}}])")
        assert guest.call("GET", page)["summary"] == "V1"
        assert organizer.call("PUT", page, 200, content)["summary"] == content["summary"]
    assert guest.call("GET", path + "/reviews") == []
    buyer.call("POST", path + "/reviews", 409, {"rating": 5})
    organizer.call("POST", events, 409, body)
    second = other.call("POST", events, 201, {**body, "location_id": stage, "title": "Other"})
    assert len(guest.call("GET", events + "?q=alpha&type=concert")) == 1
    assert len(guest.call("GET", events + "?q=%25")) == 1
    assert guest.call("GET", events + "?q=missing") == []
    assert len(guest.call("GET", events + "?from=" + start.strftime("%Y-%m-%dT%H:%M:%SZ") +
                          "&to=" + next_day.strftime("%Y-%m-%dT%H:%M:%SZ"))) == 2
    assert len(organizer.call("GET", api + "/me/events")) == 1
    other.call("PATCH", path, 403, {"description": "Чужая правка"})
    organizer.call("PATCH", path, 409, {"location_id": stage})
    bookings = api + f"/locations/{hall}/bookings"
    assert guest.call("GET", bookings)[0]["event_id"] == eid
    moved = organizer.call("PATCH", path, 200, {"location_id": stage, "starts_at": next_day.isoformat()})
    assert moved["location"]["id"] == stage and guest.call("GET", bookings) == []
    organizer.call("PATCH", path, 200, {"location_id": hall, "starts_at": start.isoformat()})

    def buy(client, qty, status, key=None, event_id=eid):
        return client.call("POST", orders, status, {"event_id": event_id, "quantity": qty},
                           {"Idempotency-Key": key} if key else {})

    for qty in (0, 6):
        buy(buyer, qty, 400)
    paid = buy(buyer, 2, 201, "cart-1")
    assert paid["total_price"] == "21.90" and len(paid["tickets"]) == 2
    assert buy(buyer, 2, 201, "cart-1")["id"] == paid["id"]
    buy(buyer, 1, 409, "cart-1")
    organizer.call("PATCH", path, 409, {"ticket_price": "12"})
    organizer.call("PATCH", path, 200, {"description": "Новая программа"})
    assert guest.call("GET", path)["available"] == 1

    gate = threading.Barrier(2)

    def last_seat(client):
        # One response must be 201 and the other 409; send both requests concurrently.
        req = urllib.request.Request(base + orders, data=json.dumps({"event_id": eid, "quantity": 1}).encode(),
                                     headers={"Content-Type": "application/json"})
        gate.wait(timeout=8)
        try:
            response = client.http.open(req, timeout=8)
        except urllib.error.HTTPError as err:
            response = err
        with response:
            return response.status

    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(last_seat, [buyer, other])) == [201, 409]
    assert guest.call("GET", path)["available"] == 0
    assert sql(f"SELECT count(*) FROM tickets JOIN orders USING(order_id) WHERE event_id={eid}") == "3"

    order_path = cabinet + "/" + str(paid["id"])
    refund = order_path + "/refunds"
    ids = [t["id"] for t in paid["tickets"]]
    other.call("GET", order_path, 404)
    other.call("POST", refund, 404, {"ticket_ids": ids})
    buyer.call("POST", refund, 409, {"ticket_ids": [ids[0], 1000000]})
    assert buyer.call("GET", order_path) == paid
    part = buyer.call("POST", refund, 200, {"ticket_ids": [ids[0]]})
    assert part["status"] == "paid" and part["total_price"] == "10.95"
    buyer.call("POST", refund, 409, {"ticket_ids": [ids[0]]})
    full = buyer.call("POST", refund, 200, {"ticket_ids": [ids[1]]})
    assert buy(buyer, 2, 201, "cart-1")["id"] == paid["id"]
    assert full["status"] == "refunded" and full["total_price"] == "0.00"
    assert all(o["id"] != paid["id"] for o in buyer.call("GET", cabinet))
    assert guest.call("GET", path)["available"] == 2
    active = buy(buyer, 1, 201)
    cancelled = organizer.call("POST", path + "/cancel")
    assert cancelled["status"] == "cancelled"
    organizer.call("POST", path + "/cancel", 409)
    guest.call("GET", path, 404)
    guest.call("GET", page, 404)
    guest.call("GET", path + "/reviews", 404)
    assert mongo(f"db.event_pages.findOne({{_id:{eid}}}).event.status") == "cancelled"
    assert guest.call("GET", bookings) == []
    assert [e["id"] for e in guest.call("GET", events)] == [second["id"]]
    buy(buyer, 1, 409)
    after = buyer.call("GET", cabinet + "/" + str(active["id"]))
    assert after["status"] == "cancelled" and after["tickets"][0]["status"] == "cancelled"
    assert buyer.call("GET", order_path)["status"] == "refunded"
    large = int(sql("INSERT INTO locations(name,address,capacity) VALUES ('Фестиваль','Центр',5) RETURNING location_id"))
    premium = organizer.call("POST", events, 201, {**body, "location_id": large, "ticket_price": "99999999.99"})
    finished = events + "/" + str(premium["id"])
    organizer.call("PUT", finished + "/page", 200, content)
    five = buy(buyer, 5, 201, event_id=premium["id"])
    sql(f"UPDATE events SET datetime=now()-interval '1 day' WHERE event_id={premium['id']}")
    submitted = buyer.call("POST", finished + "/reviews", 201, {"rating": 4, "text": "Отлично"})
    assert submitted["rating"] == 4 and len(submitted["id"]) == 24
    buyer.call("POST", finished + "/reviews", 409, {"rating": 1})
    other.call("POST", finished + "/reviews", 403, {"rating": 1})
    assert guest.call("GET", finished + "/reviews") == [submitted]
    assert guest.call("GET", finished + "/page")["rating"] == {"count": 1, "avg": 4}
    assert mongo(f"db.event_pages.findOne({{_id:{premium['id']}}}).rating.count") == "1"
    assert five["total_price"] == "499999999.95"
    # Move a fixture into the past to test the cutoff without waiting for the clock.
    old = buy(buyer, 1, 201, event_id=second["id"])
    sql(f"UPDATE events SET datetime=now()-interval '1 minute' WHERE event_id={second['id']}")
    buyer.call("POST", cabinet + f"/{old['id']}/refunds", 409, {"ticket_ids": [old["tickets"][0]["id"]]})
    other.call("POST", events + f"/{second['id']}/cancel", 409)
    buy(buyer, 1, 409, event_id=second["id"])


def main():
    env = {**os.environ, "POSTGRES_PASSWORD": secrets.token_hex(20), "COOKIE_SECURE": "false"}
    container = run("docker", "run", "--rm", "-d", "-e", "POSTGRES_PASSWORD", "-e", "POSTGRES_DB=poster_test",
                    "-p", "127.0.0.1::5432", "postgres:16", env=env, capture_output=True).stdout.strip()
    with contextlib.ExitStack() as cleanup:
        cleanup.callback(subprocess.run, ["docker", "rm", "-f", container], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
        env.update(MONGO_INITDB_ROOT_USERNAME="poster", MONGO_INITDB_ROOT_PASSWORD=secrets.token_hex(20))
        mongo_container = run("docker", "run", "--rm", "-d", "-e", "MONGO_INITDB_ROOT_USERNAME",
                              "-e", "MONGO_INITDB_ROOT_PASSWORD", "-p", "127.0.0.1::27017", "mongo:7.0",
                              env=env, capture_output=True).stdout.strip()
        cleanup.callback(subprocess.run, ["docker", "rm", "-f", mongo_container],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        mongo_port = run("docker", "port", mongo_container, "27017", capture_output=True).stdout.strip().split(":")[-1]
        mongo_cmd = ["docker", "exec", mongo_container, "sh", "-c",
                     'exec mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" '
                     '--authenticationDatabase admin test_content "$@"', "sh"]
        wait_for(lambda: subprocess.run([*mongo_cmd, "--eval", "db.runCommand({ping:1})"], capture_output=True).returncode == 0)
        run("docker", "cp", str(ROOT / "scripts/mongo/01_schema.js"), mongo_container + ":/tmp/schema.js")
        run(*mongo_cmd, "--file", "/tmp/schema.js", stdout=subprocess.DEVNULL)
        def mongo(js):
            return run(*mongo_cmd, "--eval", js, capture_output=True).stdout.strip()
        env.pop("MONGO_URI", None)
        env.update(MONGO_HOST="127.0.0.1", MONGO_PORT=mongo_port, MONGO_DB="test_content", MONGO_USER="poster",
                   MONGO_PASSWORD=env["MONGO_INITDB_ROOT_PASSWORD"])
        port = run("docker", "port", container, "5432", capture_output=True).stdout.strip().split(":")[-1]
        def sql(statement, database="poster_test"):
            return run("docker", "exec", "-i", container, "psql", "-XqAt", "-v", "ON_ERROR_STOP=1",
                       "-U", "postgres", "-d", database, input=statement, capture_output=True).stdout.strip()

        wait_for(lambda: subprocess.run(["docker", "exec", container, "pg_isready", "-h", "127.0.0.1"],
                                        capture_output=True).returncode == 0)
        sql("CREATE DATABASE legacy")
        for migration in sorted((ROOT / "migrations").glob("*.up.sql"))[:8]:
            sql(migration.read_text(), "legacy")
        sql((ROOT / "scripts/seed.sql").read_text(), "legacy")
        app_password = secrets.token_hex(20)
        # Exercise role creation both before and after the account migration.
        role_script = (ROOT / "scripts/security/roles.sql").read_text()
        def apply_roles(database):
            values = {"admin_pass": secrets.token_hex(20), "app_pass": app_password,
                      "analyst_pass": secrets.token_hex(20)}
            sql("".join(f"\\set {k} {v}\n" for k, v in values.items()) + role_script, database)
        apply_roles("legacy")
        for db_name in ("legacy", "poster_test"):
            dsn = f"postgres://postgres:{env['POSTGRES_PASSWORD']}@127.0.0.1:{port}/{db_name}?sslmode=disable"
            env.update(DATABASE_URL=dsn, DB_URL=dsn)
            run("make", "-e", "migrate", env=env)
            run("make", "-e", "migrate", env=env)
        assert sql("SELECT has_table_privilege('app_user','user_sessions','INSERT')", "legacy") == 't'
        assert sql("SELECT has_table_privilege('analyst_user','user_credentials','SELECT')", "legacy") == 'f'
        apply_roles("poster_test")
        assert sql("SELECT has_table_privilege('analyst_user','user_credentials','SELECT')") == 'f'
        assert sql("SELECT has_table_privilege('analyst_user','user_sessions','SELECT')") == 'f'
        env["DATABASE_URL"] = f"postgres://app_user:{app_password}@127.0.0.1:{port}/poster_test?sslmode=disable"
        assert sql("SELECT count(*) FROM users", "legacy") == "3"
        assert sql("SELECT count(*) FROM location_bookings", "legacy") == "2"
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        env["SERVER_PORT"] = str(port)
        base = f"http://127.0.0.1:{port}"
        with subprocess.Popen([ROOT / "bin/api"], env=env, cwd=ROOT) as process:
            try:
                wait_for(lambda: Client(base).call("GET", "/readyz") == {"status": "ok"})
                exercise(base, sql, mongo)
                run("docker", "stop", mongo_container, stdout=subprocess.DEVNULL)
                Client(base).call("GET", "/readyz", 503)
                Client(base).call("GET", "/api/v1/performers", 503)
                Client(base).call("GET", "/api/v1/events", 200)
                run("docker", "stop", container, stdout=subprocess.DEVNULL)
                Client(base).call("GET", "/readyz", 503)
            finally:
                if process.poll() is None:
                    process.terminate()
    print("OK: PostgreSQL, MongoDB и сквозные сценарии HTTP API")


if __name__ == "__main__":
    main()
