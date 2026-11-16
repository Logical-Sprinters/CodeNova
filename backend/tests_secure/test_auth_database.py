from concurrent.futures import ThreadPoolExecutor
import json

import pytest
from sqlalchemy import select

from app import config, auth_service
from app.database import documents, engine
from app.storage import STORE_LOCK, read_json, write_json


def test_real_login_identity_and_spoofing_rejection(client, headers):
    assert (
        client.get("/api/v1/auth/me", headers=headers["creator"]).json()["user"]["role"]
        == "creator"
    )
    assert (
        client.get(
            "/api/v1/reviews", headers={"X-User-Id": "u2", "X-User-Role": "reviewer"}
        ).status_code
        == 401
    )
    assert (
        client.get(
            "/api/v1/reviews", headers={"Authorization": "Bearer forged"}
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"email": "creator@brandguard.demo", "password": "wrong"},
        ).status_code
        == 401
    )
    response = client.post(
        "/api/v1/library/facts",
        headers=headers["creator"] | {"X-User-Role": "admin"},
        json={"title": "Fact", "content": "Verified source text"},
    )
    assert response.status_code == 403
    stored = auth_service.load("auth_users")
    assert len(stored) == 2
    assert all(
        row["password_hash"].startswith("pbkdf2_sha256$600000$") for row in stored
    )
    assert "Demo@12345" not in json.dumps(stored)


def test_signup_creator_only_validation_and_duplicate(client):
    body = {"name": "New User", "email": "new@example.com", "password": "Password123!"}
    assert (
        client.post("/api/v1/auth/signup", json=body | {"role": "admin"}).status_code
        == 422
    )
    assert (
        client.post("/api/v1/auth/signup", json=body | {"name": "  "}).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/auth/signup", json=body | {"password": "short"}
        ).status_code
        == 422
    )
    assert (
        client.post("/api/v1/auth/signup", json=body | {"email": "no-at"}).status_code
        == 422
    )
    response = client.post("/api/v1/auth/signup", json=body)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["user"]["role"] == "creator"
    assert "password_hash" not in result["user"]
    assert client.post("/api/v1/auth/signup", json=body).status_code == 409
    assert (
        client.get(
            "/api/v1/auth/me",
            headers={"Authorization": "Bearer " + result["access_token"]},
        ).status_code
        == 200
    )


def test_refresh_rotation_and_logout_revoke_access_and_refresh(client, tokens):
    old = tokens["creator"]
    refreshed = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": old["refresh_token"]}
    )
    assert refreshed.status_code == 200
    current = refreshed.json()
    assert current["access_token"] != old["access_token"]
    assert (
        client.get(
            "/api/v1/auth/me",
            headers={"Authorization": "Bearer " + old["access_token"]},
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/api/v1/auth/refresh", json={"refresh_token": old["refresh_token"]}
        ).status_code
        == 401
    )
    headers = {"Authorization": "Bearer " + current["access_token"]}
    assert client.post("/api/v1/auth/logout", headers=headers).status_code == 200
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401
    assert (
        client.post(
            "/api/v1/auth/refresh", json={"refresh_token": current["refresh_token"]}
        ).status_code
        == 401
    )


def test_local_recovery_does_not_pretend_to_send_email(client):
    response = client.post("/api/v1/auth/recover", json={"email": "new@example.com"})
    assert response.status_code == 503
    assert "requires configured Supabase" in response.json()["detail"]


def test_login_rate_limit(client):
    for _ in range(10):
        assert (
            client.post(
                "/api/v1/auth/login",
                json={"email": "nobody@example.com", "password": "wrong"},
            ).status_code
            == 401
        )
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"email": "nobody@example.com", "password": "wrong"},
        ).status_code
        == 429
    )


def test_database_nested_rollback_and_no_partial_records(client):
    p = config.DATA_DIR / "transaction_example.json"
    write_json(p, {"count": 0})
    with pytest.raises(RuntimeError):
        with STORE_LOCK:
            write_json(p, {"count": 1})
            write_json(config.DATA_DIR / "second_example.json", [{"id": "a"}])
            raise RuntimeError("abort workflow")
    assert read_json(p, {}) == {"count": 0}
    assert read_json(config.DATA_DIR / "second_example.json", []) == []
    assert not p.exists()
    assert (config.DATA_DIR / "brandguard.sqlite3").is_file()
    with engine().connect() as conn:
        assert conn.execute(
            select(documents.c.payload).where(documents.c.name == "transaction_example")
        ).scalar_one() == {"count": 0}


def test_concurrent_database_workflows_do_not_lose_updates(client):
    p = config.DATA_DIR / "counter.json"
    write_json(p, {"count": 0})

    def increment(_):
        with STORE_LOCK:
            data = read_json(p, {})
            write_json(p, {"count": data["count"] + 1})

    with ThreadPoolExecutor(max_workers=6) as workers:
        list(workers.map(increment, range(36)))
    assert read_json(p, {})["count"] == 36


def test_duplicate_ids_rollback_collection(client):
    p = config.DATA_DIR / "duplicates.json"
    write_json(p, [{"id": "a", "value": 1}])
    with pytest.raises(ValueError):
        write_json(p, [{"id": "a"}, {"id": "a"}])
    assert read_json(p, []) == [{"id": "a", "value": 1}]


def test_sql_backup_restore_roundtrip(client, tmp_path):
    from manage import backup, restore

    p = config.DATA_DIR / "example.json"
    write_json(p, [{"id": "one", "value": "original"}])
    target = tmp_path / "private-backup.json"
    backup(target)
    write_json(p, [])
    restore(target)
    assert read_json(p, [])[0]["value"] == "original"
    with pytest.raises(FileExistsError):
        backup(target)


def test_demo_flag_public_status_has_no_secrets(client, monkeypatch):
    monkeypatch.setattr(config, "SEED_DEMO_USERS", False)
    status = client.get("/api/v1/auth/config").json()
    assert status["demo_accounts_enabled"] is False
    assert "key" not in json.dumps(status).lower()
