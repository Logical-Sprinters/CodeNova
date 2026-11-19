"""Isolated default-mode tests: SQL persistence + bearer authentication, no ID bypass."""

import pytest
from fastapi.testclient import TestClient

from app import config, auth
from app.approval import store as approval_store
from app.audit import store as audit_store
from app.receipts import store as receipt_store
from app.rules_store import store as rule_store
from app.routers import authentication
from app.main import app


@pytest.fixture(autouse=True)
def secure_store(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "DATA_DIR", tmp_path / "db")
    monkeypatch.setattr(config, "DATABASE_URL", "")
    monkeypatch.setattr(config, "AUTH_PROVIDER", "local")
    monkeypatch.setattr(config, "STORAGE_BACKEND", "database")
    monkeypatch.setattr(config, "ALLOW_LEGACY_DEMO_HEADERS", False)
    monkeypatch.setattr(config, "SEED_DEMO_USERS", True)
    monkeypatch.setattr(config, "JWT_SECRET", "tests-only-" + "secure-secret-" * 4)
    monkeypatch.setattr(config, "AI_PROVIDER", "disabled")
    monkeypatch.setattr(config, "AI_API_KEY", "")
    monkeypatch.setattr(config, "AI_BASE_URL", "https://api.openai.com/v1")
    monkeypatch.setattr(config, "AI_MODEL", "gpt-5.4-mini")
    monkeypatch.setattr(config, "AI_DATA_COLLECTION", "")
    for module, attribute, filename in (
        (auth, "USERS_FILE", "users.json"),
        (approval_store, "STORE_FILE", "review_records.json"),
        (audit_store, "AUDIT_FILE", "audit_log.json"),
        (receipt_store, "RECEIPTS_FILE", "receipts.json"),
        (rule_store, "RULES_FILE", "brand_rules.json"),
    ):
        monkeypatch.setattr(module, attribute, config.DATA_DIR / filename)
    authentication._attempts.clear()
    yield
    from app.database import _engines

    for url, db in list(_engines.items()):
        if str(tmp_path) in url:
            db.dispose()
            del _engines[url]


@pytest.fixture
def client():
    with TestClient(app) as client:
        yield client


@pytest.fixture
def tokens(client):
    result = {}
    for role in ("creator", "reviewer"):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": f"{role}@brandguard.demo", "password": "Demo@12345"},
        )
        assert response.status_code == 200, response.text
        result[role] = response.json()
    return result


@pytest.fixture
def headers(tokens):
    return {
        role: {"Authorization": "Bearer " + payload["access_token"]}
        for role, payload in tokens.items()
    }
