import asyncio
import os
import time
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

SERVICE_NAME = os.getenv("SERVICE_NAME", "backend4")
# no default: credentials come from the environment (a Secrets Manager secret in prod)
DATABASE_URL = os.environ["DATABASE_URL"]
HEARTBEAT_SECONDS = int(os.getenv("HEARTBEAT_SECONDS", "10"))
CORS_ORIGINS = [o for o in os.getenv("CORS_ORIGINS", "").split(",") if o]

SCHEMA = """
CREATE TABLE IF NOT EXISTS service_status (
    name      TEXT PRIMARY KEY,
    status    TEXT NOT NULL,
    last_seen TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS status_log (
    id         SERIAL PRIMARY KEY,
    service    TEXT NOT NULL,
    status     TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

UPSERT = """
INSERT INTO service_status (name, status, last_seen) VALUES (%s, %s, now())
ON CONFLICT (name) DO UPDATE SET status = EXCLUDED.status, last_seen = now()
"""


def save_status(status: str, log: bool = False) -> None:
    with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
        conn.execute(UPSERT, (SERVICE_NAME, status))
        if log:
            conn.execute(
                "INSERT INTO status_log (service, status) VALUES (%s, %s)",
                (SERVICE_NAME, status),
            )


def init_db(retries: int = 30, delay: float = 2.0) -> None:
    for attempt in range(1, retries + 1):
        try:
            with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
                conn.execute(SCHEMA)
            save_status("live", log=True)
            return
        except psycopg.Error as exc:
            print(f"[{SERVICE_NAME}] db not ready ({attempt}/{retries}): {exc}", flush=True)
            time.sleep(delay)
    print(f"[{SERVICE_NAME}] starting without db", flush=True)


async def heartbeat() -> None:
    while True:
        await asyncio.sleep(HEARTBEAT_SECONDS)
        try:
            await asyncio.to_thread(save_status, "live")
        except psycopg.Error as exc:
            print(f"[{SERVICE_NAME}] heartbeat failed: {exc}", flush=True)


@asynccontextmanager
async def lifespan(_: FastAPI):
    await asyncio.to_thread(init_db)
    task = asyncio.create_task(heartbeat())
    yield
    task.cancel()
    try:
        await asyncio.to_thread(save_status, "off", True)
    except psycopg.Error:
        pass


app = FastAPI(title=SERVICE_NAME, lifespan=lifespan)
if CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware, allow_origins=CORS_ORIGINS, allow_methods=["GET"], allow_headers=["*"]
    )


@app.get("/status")
def status():
    try:
        save_status("live")
        db_ok = True
    except psycopg.Error:
        db_ok = False
    return {"service": SERVICE_NAME, "status": "live", "message": f"{SERVICE_NAME} live", "db": db_ok}


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
    return response


@app.get("/history")
def history(
    service: str | None = Query(None, pattern=r"^[A-Za-z0-9_-]{1,32}$"),
    limit: int = Query(20, ge=1, le=100),
):
    """Start/stop events from Postgres. service=all returns every backend."""
    name = service or SERVICE_NAME
    query = "SELECT service, status, created_at FROM status_log"
    params: tuple = ()
    if name != "all":
        query += " WHERE service = %s"
        params = (name,)
    query += " ORDER BY id DESC LIMIT %s"
    try:
        with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
            rows = conn.execute(query, (*params, limit)).fetchall()
    except psycopg.Error:
        raise HTTPException(status_code=503, detail="database unavailable")
    return [{"service": s, "status": st, "created_at": c.isoformat()} for s, st, c in rows]


@app.get("/health")
def health():
    return {"status": "ok"}
