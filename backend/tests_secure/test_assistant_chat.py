"""Grounded BrandGuard AI Assistant chat endpoint tests."""

import json

import httpx

from app import config


def test_assistant_requires_auth(client):
    res = client.post("/api/v1/assistant/chat", json={"message": "Summarize Acme rules"})
    assert res.status_code == 401


def test_assistant_deterministic_fallback_checks_copy_and_cites_rules(client, headers):
    res = client.post(
        "/api/v1/assistant/chat",
        headers=headers["creator"],
        json={
            "message": "Check copy: Our solution is 100% safe and guaranteed!",
            "brand_name": "Acme",
        },
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["mode"] == "deterministic_fallback"
    assert body["ai_used"] is False
    assert any(h.get("rule_id") == "BG-002" for h in body["deterministic_hits"])
    assert "BG-002" in body["citations"]
    assert "BG-002" in body["reply"]


def test_assistant_live_ai_filters_invented_citations_and_preserves_valid(
    client, headers, monkeypatch
):
    class _FakeResp:
        status_code = 200
        is_error = False
        text = ""

        @staticmethod
        def json():
            return {
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {
                            "content": json.dumps(
                                {
                                    "reply": "Replace 'guaranteed' with 'designed for high availability' per BG-002, then run a full Brand Check for reviewer approval.",
                                    "cited_ids": ["BG-002", "FAKE-999"],
                                }
                            )
                        },
                    }
                ]
            }

    monkeypatch.setattr(config, "AI_PROVIDER", "gemini")
    monkeypatch.setattr(config, "AI_API_KEY", "test-only-key")
    monkeypatch.setattr(
        config,
        "AI_BASE_URL",
        "https://generativelanguage.googleapis.com/v1beta/openai",
    )
    monkeypatch.setattr(config, "AI_MODEL", "gemini-3.5-flash-lite")
    monkeypatch.setattr(httpx, "post", lambda *args, **kwargs: _FakeResp())

    res = client.post(
        "/api/v1/assistant/chat",
        headers=headers["reviewer"],
        json={
            "message": "Rewrite: Our cloud is guaranteed!",
            "brand_name": "Acme",
            "history": [{"role": "user", "content": "Hi"}],
        },
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["mode"] == "ai"
    assert body["ai_used"] is True
    assert body["provider"] == "gemini"
    assert body["model"] == "gemini-3.5-flash-lite"
    assert "BG-002" in body["citations"]
    assert "FAKE-999" not in body["citations"]


def test_assistant_falls_back_gracefully_on_provider_rate_limit(
    client, headers, monkeypatch
):
    class _RateLimitedResp:
        status_code = 429
        is_error = True
        text = "rate limited"

    monkeypatch.setattr(config, "AI_PROVIDER", "gemini")
    monkeypatch.setattr(config, "AI_API_KEY", "test-only-key")
    monkeypatch.setattr(config, "AI_MODEL", "gemini-3.5-flash-lite")
    monkeypatch.setattr(httpx, "post", lambda *args, **kwargs: _RateLimitedResp())

    res = client.post(
        "/api/v1/assistant/chat",
        headers=headers["creator"],
        json={"message": "Explain 60-min amend and seals", "brand_name": "Acme"},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["mode"] == "deterministic_fallback"
    assert body["ai_used"] is False
    assert "60 minutes" in body["reply"]


def test_assistant_works_with_existing_checks_for_creator_and_reviewer(
    client, headers
):
    created = client.post(
        "/api/v1/brand/check",
        headers=headers["creator"],
        json={
            "brand_name": "Acme",
            "content": "Our product is 100% safe for everyone.",
        },
    )
    assert created.status_code == 200, created.text

    for role in ("creator", "reviewer"):
        res = client.post(
            "/api/v1/assistant/chat",
            headers=headers[role],
            json={"message": "Show queue status for Acme", "brand_name": "Acme"},
        )
        assert res.status_code == 200, (role, res.text)
        body = res.json()
        assert "1 total" in body["reply"]
