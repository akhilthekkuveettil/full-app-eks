from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import main

client = TestClient(main.app)


def fake_connection(rows=None):
    conn = MagicMock()
    conn.__enter__.return_value = conn
    conn.execute.return_value.fetchall.return_value = rows or []
    return conn


def test_health():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_security_headers():
    res = client.get("/health")
    assert res.headers["X-Content-Type-Options"] == "nosniff"
    assert res.headers["Cross-Origin-Resource-Policy"] == "same-origin"


def test_status_db_up():
    with patch.object(main.psycopg, "connect", return_value=fake_connection()):
        body = client.get("/status").json()
    assert body["service"] == main.SERVICE_NAME
    assert body["message"] == f"{main.SERVICE_NAME} live"
    assert body["db"] is True


def test_status_db_down_still_live():
    with patch.object(main.psycopg, "connect", side_effect=psycopg.OperationalError("down")):
        body = client.get("/status").json()
    assert body["status"] == "live"
    assert body["db"] is False


def test_history_returns_rows():
    created = datetime(2026, 1, 1, tzinfo=timezone.utc)
    conn = fake_connection([("backend2", "live", created)])
    with patch.object(main.psycopg, "connect", return_value=conn):
        res = client.get("/history", params={"service": "all", "limit": 5})
    assert res.status_code == 200
    assert res.json() == [
        {"service": "backend2", "status": "live", "created_at": created.isoformat()}
    ]
    # "all" must not add a WHERE clause
    assert "WHERE" not in conn.execute.call_args.args[0]


def test_history_filters_by_service():
    conn = fake_connection()
    with patch.object(main.psycopg, "connect", return_value=conn):
        client.get("/history", params={"service": "backend3"})
    query, params = conn.execute.call_args.args
    assert "WHERE service = %s" in query
    assert params == ("backend3", 20)


def test_history_db_down_returns_503():
    with patch.object(main.psycopg, "connect", side_effect=psycopg.OperationalError("down")):
        assert client.get("/history").status_code == 503


@pytest.mark.parametrize(
    "params",
    [{"service": "x; DROP TABLE status_log"}, {"limit": 0}, {"limit": 101}],
)
def test_history_rejects_bad_input(params):
    assert client.get("/history", params=params).status_code == 422
