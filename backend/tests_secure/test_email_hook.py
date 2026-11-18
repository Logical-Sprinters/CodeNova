"""Signed Auth email protocol/relay tests; mocks are not inbox-delivery proof."""

from datetime import datetime, timedelta, timezone
import base64
import json

import httpx
import pytest
from standardwebhooks import Webhook

from app import config
from app.routers import email_delivery
from app.storage import read_json

SECRET = "whsec_" + base64.b64encode(b"test-hook-key-32-bytes-for-tests!!").decode()
PAYLOAD = {
    "user": {"id": "test-user", "email": "owner@example.com"},
    "email_data": {
        "email_action_type": "recovery",
        "token_hash": "a" * 64,
        "redirect_to": "https://attacker.example/steal",
    },
}


def signed(payload, identifier="wh-test-1", timestamp=None):
    timestamp = timestamp or datetime.now(timezone.utc)
    raw = json.dumps(payload)
    return raw, {
        "webhook-id": identifier,
        "webhook-timestamp": str(int(timestamp.timestamp())),
        "webhook-signature": Webhook(SECRET).sign(identifier, timestamp, raw),
        "Content-Type": "application/json",
    }


def enable(monkeypatch, response_status=200):
    monkeypatch.setattr(config, "SUPABASE_EMAIL_HOOK_SECRET", SECRET)
    monkeypatch.setattr(config, "RESEND_API_KEY", "mock-relay-key")
    monkeypatch.setattr(config, "RESEND_API_URL", "https://relay.example/api")
    monkeypatch.setattr(config, "EMAIL_FROM", "BrandGuard <noreply@example.com>")
    monkeypatch.setattr(config, "PUBLIC_APP_URL", "https://brandguard.example")
    monkeypatch.setattr(
        config, "AUTH_REDIRECT_URL", "https://brandguard.example/auth/reset"
    )
    monkeypatch.setattr(config, "SUPABASE_URL", "https://test-project.supabase.co")
    calls = []

    def post(url, **kwargs):
        calls.append((url, kwargs))
        return httpx.Response(
            response_status,
            request=httpx.Request("POST", url),
            json={"id": "receipt-1"},
        )

    monkeypatch.setattr(email_delivery.httpx, "post", post)
    return calls


def test_signed_recovery_uses_only_controlled_redirect(client, monkeypatch):
    calls = enable(monkeypatch)
    raw, headers = signed(PAYLOAD)
    response = client.post("/api/v1/auth/hooks/email", content=raw, headers=headers)
    assert response.status_code == 200 and response.json() == {}
    assert len(calls) == 1
    url, args = calls[0]
    assert url == "https://relay.example/api/emails"
    assert "attacker.example" not in args["json"]["html"]
    assert "brandguard.example%2Fauth%2Freset" in args["json"]["html"]
    assert args["json"]["to"] == ["owner@example.com"]
    assert args["headers"]["Authorization"] == "Bearer mock-relay-key"
    stored = read_json(config.DATA_DIR / "auth_email_events.json", [])
    assert len(stored) == 1
    assert "owner@example.com" not in json.dumps(stored)
    assert "a" * 64 not in json.dumps(stored)


def test_identical_signed_retry_does_not_resend(client, monkeypatch):
    calls = enable(monkeypatch)
    raw, headers = signed(PAYLOAD)
    for _ in range(2):
        assert (
            client.post(
                "/api/v1/auth/hooks/email", content=raw, headers=headers
            ).status_code
            == 200
        )
    assert len(calls) == 1


@pytest.mark.parametrize(
    "issue", ["missing", "wrong-secret", "old", "future", "tampered"]
)
def test_invalid_signature_never_sends(client, monkeypatch, issue):
    calls = enable(monkeypatch)
    now = datetime.now(timezone.utc)
    stamp = (
        now - timedelta(minutes=15)
        if issue == "old"
        else now + timedelta(minutes=15) if issue == "future" else now
    )
    raw, headers = signed(PAYLOAD, timestamp=stamp)
    if issue == "missing":
        headers = {}
    elif issue == "wrong-secret":
        headers["webhook-signature"] = "v1,aW52YWxpZA=="
    elif issue == "tampered":
        raw += " "
    assert (
        client.post(
            "/api/v1/auth/hooks/email", content=raw, headers=headers
        ).status_code
        == 401
    )
    assert not calls


@pytest.mark.parametrize(
    "action",
    [
        "signup",
        "invite",
        "magiclink",
        "reauthentication",
        "password_changed_notification",
    ],
)
def test_supported_auth_actions(client, monkeypatch, action):
    calls = enable(monkeypatch)
    payload = {
        "user": PAYLOAD["user"],
        "email_data": PAYLOAD["email_data"]
        | {"email_action_type": action, "token": "123456"},
    }
    raw, headers = signed(payload)
    assert (
        client.post(
            "/api/v1/auth/hooks/email", content=raw, headers=headers
        ).status_code
        == 200
    )
    assert len(calls) == 1


def test_relay_quota_failure_not_reported_as_success(client, monkeypatch):
    calls = enable(monkeypatch, response_status=429)
    raw, headers = signed(PAYLOAD)
    assert (
        client.post(
            "/api/v1/auth/hooks/email", content=raw, headers=headers
        ).status_code
        == 503
    )
    assert len(calls) == 1
    assert read_json(config.DATA_DIR / "auth_email_events.json", []) == []


def test_unsigned_body_size_is_bounded(client, monkeypatch):
    calls = enable(monkeypatch)
    assert (
        client.post("/api/v1/auth/hooks/email", content=b"a" * 65537).status_code == 413
    )
    assert not calls


def test_bad_signed_recipient_is_rejected(client, monkeypatch):
    calls = enable(monkeypatch)
    raw, headers = signed(
        PAYLOAD | {"user": {"email": "bad\r\nCC: attacker@example.com"}}
    )
    assert (
        client.post(
            "/api/v1/auth/hooks/email", content=raw, headers=headers
        ).status_code
        == 400
    )
    assert not calls


def test_server_metadata_never_changes_from_or_redirect(client, monkeypatch):
    calls = enable(monkeypatch)
    payload = {
        "user": PAYLOAD["user"]
        | {"user_metadata": {"email_from": "attacker@example.com"}},
        "email_data": PAYLOAD["email_data"],
    }
    raw, headers = signed(payload)
    assert (
        client.post(
            "/api/v1/auth/hooks/email", content=raw, headers=headers
        ).status_code
        == 200
    )
    assert calls[0][1]["json"]["from"] == "BrandGuard <noreply@example.com>"
