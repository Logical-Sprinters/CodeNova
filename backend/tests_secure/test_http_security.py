"""Static policy contracts; browser execution is checked separately at release."""

import base64
import hashlib
import re

import pytest

from app.routers.email_delivery import email_content
from app import config


@pytest.mark.parametrize(
    "path", ["/health", "/auth/reset", "/auth/confirm", "/api/v1/auth/config"]
)
def test_defensive_response_headers(client, path):
    response = client.get(path)
    assert response.status_code == 200
    headers = response.headers
    assert headers["x-content-type-options"] == "nosniff"
    assert headers["referrer-policy"] == "no-referrer"
    assert headers["x-frame-options"] == "DENY"
    policy = headers["content-security-policy"]
    assert "object-src 'none'" in policy
    assert "frame-ancestors 'none'" in policy
    scripts = next(p for p in policy.split(";") if p.strip().startswith("script-src "))
    assert "'unsafe-inline'" not in scripts
    assert "'unsafe-eval'" not in scripts
    assert "https:" not in scripts


@pytest.mark.parametrize("path", ["/auth/reset", "/auth/confirm"])
def test_auth_callback_scripts_match_csp_without_persisting_tokens(client, path):
    response = client.get(path)
    assert response.headers["cache-control"] == "no-store"
    assert "history.replaceState" in response.text
    assert "localStorage" not in response.text
    assert "sessionStorage" not in response.text
    for script in re.findall(r"<script>(.*?)</script>", response.text, re.DOTALL):
        digest = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        assert "'sha256-" + digest + "'" in response.headers["content-security-policy"]


@pytest.mark.parametrize(
    "action,target",
    [
        ("signup", "/auth/confirm"),
        ("magiclink", "/auth/confirm"),
        ("recovery", "/auth/reset"),
        ("invite", "/auth/reset"),
    ],
)
def test_auth_email_destinations_are_server_owned(monkeypatch, action, target):
    monkeypatch.setattr(config, "PUBLIC_APP_URL", "https://brandguard.example")
    monkeypatch.setattr(
        config, "AUTH_REDIRECT_URL", "https://brandguard.example/auth/reset"
    )
    monkeypatch.setattr(config, "SUPABASE_URL", "https://project.supabase.co")
    result = email_content(
        {
            "user": {"email": "test@example.com"},
            "email_data": {
                "email_action_type": action,
                "token_hash": "a" * 64,
                "redirect_to": "https://attacker.example",
            },
        }
    )
    assert "brandguard.example" + target.replace("/", "%2F") in result["html"]
    assert "attacker.example" not in result["html"]
