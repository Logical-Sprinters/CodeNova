"""Tests always use temporary stores, never the app's real demo records."""

import shutil

import pytest
from fastapi.testclient import TestClient

from app import auth, config
from app.approval import store as approval_store
from app.audit import store as audit_store
from app.config import DEFAULT_DATA_DIR
from app.main import app
from app.receipts import store as receipt_store
from app.rules_store import store as rule_store


@pytest.fixture(autouse=True)
def isolated_stores(tmp_path, monkeypatch):
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    # Never inherit a developer/server's cloud .env or runtime data directory.
    monkeypatch.setattr(config, "STORAGE_BACKEND", "json")
    monkeypatch.setattr(config, "AUTH_PROVIDER", "local")
    monkeypatch.setattr(config, "DATABASE_URL", "")
    monkeypatch.setattr(config, "AI_PROVIDER", "disabled")
    monkeypatch.setattr(config, "AI_API_KEY", "")
    monkeypatch.setattr(config, "AI_BASE_URL", "https://api.openai.com/v1")
    monkeypatch.setattr(config, "AI_MODEL", "gpt-5.4-mini")
    monkeypatch.setattr(config, "AI_DATA_COLLECTION", "")
    monkeypatch.setattr(config, "ALLOW_LEGACY_DEMO_HEADERS", True)
    monkeypatch.setattr(config, "DATA_DIR", data_dir)
    for name in ("users.json", "brand_rules.json"):
        shutil.copy2(DEFAULT_DATA_DIR / name, data_dir / name)
    for name in ("review_records.json", "receipts.json", "audit_log.json"):
        (data_dir / name).write_text("[]\n", encoding="utf-8")

    for module, attribute, filename in (
        (auth, "USERS_FILE", "users.json"),
        (approval_store, "STORE_FILE", "review_records.json"),
        (audit_store, "AUDIT_FILE", "audit_log.json"),
        (receipt_store, "RECEIPTS_FILE", "receipts.json"),
        (rule_store, "RULES_FILE", "brand_rules.json"),
    ):
        monkeypatch.setattr(module, attribute, data_dir / filename)

    # Catch accidental repository-root/CWD assumptions in routes and tests.
    monkeypatch.chdir(tmp_path)
    yield data_dir


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def creator_headers():
    return {"X-User-Id": "u1"}


@pytest.fixture
def reviewer_headers():
    return {"X-User-Id": "u2"}
