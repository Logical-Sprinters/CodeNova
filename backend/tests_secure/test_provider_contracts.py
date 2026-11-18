"""Provider contracts use mocks only: these are NOT live Supabase/OpenAI tests."""

import json
import httpx
import jwt
import pytest

from app import auth_service, config
from app.checks.llm import verifier

FACT = {
    "id": "fact-one",
    "brand_name": "Acme",
    "title": "Acme pricing",
    "content": "Acme costs 49 dollars per month.",
    "verified": True,
    "enabled": True,
    "source_url": "https://example.com/pricing",
}
CITE = {"passage_id": "fact-one:0", "quote": "49 dollars per month"}


def enable_ai(monkeypatch):
    monkeypatch.setattr(config, "AI_PROVIDER", "openai")
    monkeypatch.setattr(config, "AI_API_KEY", "mock-only-key")


def result(status="supported"):
    return {
        "status": status,
        "message": "Compared supplied evidence.",
        "citations": [dict(CITE)],
        "findings": [],
    }


def mock_completion(monkeypatch, output, finish="stop", refusal=None):
    def post(url, **kwargs):
        payload = kwargs["json"]
        assert payload["response_format"]["type"] == "json_schema"
        assert payload["response_format"]["json_schema"]["strict"] is True
        assert payload["store"] is False
        return httpx.Response(
            200,
            request=httpx.Request("POST", url),
            json={
                "choices": [
                    {
                        "finish_reason": finish,
                        "message": {"content": json.dumps(output), "refusal": refusal},
                    }
                ]
            },
        )

    monkeypatch.setattr(verifier.httpx, "post", post)


def test_retrieval_excludes_unverified_and_reaches_later_passages(client):
    later = FACT | {
        "content": "unrelated sentence. " * 400 + "Acme costs 49 dollars per month."
    }
    passages = verifier.retrieve_facts(
        "Acme costs dollars monthly",
        facts=[later, FACT | {"id": "unverified", "verified": False}],
    )
    assert all(p["id"] == "fact-one" for p in passages)
    assert any("49 dollars" in p["_excerpt"] for p in passages)


def test_missing_access_or_evidence_never_calls_provider(client, monkeypatch):
    monkeypatch.setattr(
        verifier.httpx, "post", lambda *a, **k: pytest.fail("Unexpected provider call")
    )
    assert (
        verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])[
            "status"
        ]
        == "abstained"
    )
    enable_ai(monkeypatch)
    assert (
        verifier.run_ai_verification(
            "unrelated content", brand_facts=[FACT | {"verified": False}]
        )["status"]
        == "abstained"
    )
    assert (
        verifier.run_ai_verification("a" * 12001, brand_facts=[FACT])["status"]
        == "abstained"
    )


def test_valid_model_output_has_verbatim_quotes_and_hash(client, monkeypatch):
    enable_ai(monkeypatch)
    mock_completion(monkeypatch, result())
    output = verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])
    assert output["status"] == "supported"
    assert output["citations"][0]["quote"] in FACT["content"]
    assert len(output["citations"][0]["source_hash"]) == 64


def test_grounded_model_finding_maps_to_exact_content_span(client, monkeypatch):
    enable_ai(monkeypatch)
    data = result("needs_review")
    data["findings"] = [
        {
            "claim": "Acme costs 10 dollars",
            "message": "The cited price is 49, not 10.",
            "severity": "review",
            "citations": [dict(CITE)],
        }
    ]
    mock_completion(monkeypatch, data)
    text = "Offer: Acme costs 10 dollars today."
    output = verifier.run_ai_verification(text, brand_facts=[FACT])
    assert output["status"] == "needs_review"
    f = output["findings"][0]
    assert text[f["start_index"] : f["end_index"]] == f["evidence"]


@pytest.mark.parametrize(
    "invalid",
    [
        {"status": "made_up"},
        result() | {"citations": []},
        result() | {"citations": [CITE | {"passage_id": "invented"}]},
        result() | {"citations": [CITE | {"quote": "fabricated quotation"}]},
        result("needs_review"),
        result()
        | {
            "findings": [
                {
                    "claim": "not in submission",
                    "message": "bad",
                    "severity": "review",
                    "citations": [CITE],
                }
            ]
        },
        ["not", "an", "object"],
    ],
)
def test_bad_provider_results_abstain_instead_of_passing(client, monkeypatch, invalid):
    enable_ai(monkeypatch)
    mock_completion(monkeypatch, invalid)
    assert (
        verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])[
            "status"
        ]
        == "abstained"
    )


def test_provider_timeout_and_refusal_abstain(client, monkeypatch):
    enable_ai(monkeypatch)

    def fail(*a, **k):
        raise httpx.ReadTimeout("mock timeout")

    monkeypatch.setattr(verifier.httpx, "post", fail)
    assert (
        verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])[
            "status"
        ]
        == "abstained"
    )
    mock_completion(monkeypatch, result(), refusal="Cannot comply")
    assert (
        verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])[
            "status"
        ]
        == "abstained"
    )
    mock_completion(monkeypatch, result(), finish="length")
    assert (
        verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])[
            "status"
        ]
        == "abstained"
    )


def test_supabase_adapter_role_is_server_metadata_and_logout_denial(
    client, monkeypatch
):
    monkeypatch.setattr(config, "AUTH_PROVIDER", "supabase")
    monkeypatch.setattr(
        config, "AUTH_REDIRECT_URL", "https://api.example.com/auth/reset"
    )
    monkeypatch.setattr(config, "SUPABASE_URL", "https://mock-project.supabase.co")
    monkeypatch.setattr(config, "SUPABASE_PUBLISHABLE_KEY", "mock-publishable")
    token = jwt.encode(
        {"sub": "remote-one", "session_id": "remote-session-one"},
        "mock-only-" * 5,
        algorithm="HS256",
    )
    remote = {
        "id": "remote-one",
        "email": "remote@example.com",
        "user_metadata": {"name": "Remote", "brandguard_role": "admin"},
        "app_metadata": {},
    }
    calls = []

    def provider(method, url, **kwargs):
        calls.append((method, url, kwargs))
        assert kwargs["headers"]["apikey"] == "mock-publishable"
        data = (
            remote
            if url.endswith("/user")
            else (
                {
                    "access_token": token,
                    "refresh_token": "remote-refresh-token",
                    "expires_in": 3600,
                    "token_type": "bearer",
                    "user": remote,
                }
                if "token?" in url
                else {}
            )
        )
        return httpx.Response(200, request=httpx.Request(method, url), json=data)

    monkeypatch.setattr(auth_service.httpx, "request", provider)
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "remote@example.com", "password": "password123"},
    )
    assert login.status_code == 200, login.text
    assert login.json()["user"]["role"] == "creator"
    h = {"Authorization": "Bearer " + token}
    assert client.get("/api/v1/auth/me", headers=h).status_code == 200
    assert (
        client.post(
            "/api/v1/library/facts",
            headers=h,
            json={"title": "Source", "content": "Text"},
        ).status_code
        == 403
    )
    remote["app_metadata"] = {"brandguard_role": "reviewer"}
    assert client.get("/api/v1/auth/me", headers=h).json()["user"]["role"] == "reviewer"
    assert (
        client.post(
            "/api/v1/auth/recover", json={"email": "remote@example.com"}
        ).status_code
        == 200
    )
    assert client.post("/api/v1/auth/logout", headers=h).status_code == 200
    assert client.get("/api/v1/auth/me", headers=h).status_code == 401
    assert any("logout?scope=local" in c[1] for c in calls)


def test_openrouter_uses_private_routing_and_strict_evidence(client, monkeypatch):
    enable_ai(monkeypatch)
    monkeypatch.setattr(config, "AI_PROVIDER", "openrouter")
    monkeypatch.setattr(config, "AI_MODEL", "openai/gpt-5.4-mini")
    monkeypatch.setattr(config, "AI_BASE_URL", "https://openrouter.ai/api/v1")
    calls = []

    def post(url, **kwargs):
        calls.append((url, kwargs))
        return httpx.Response(
            200,
            request=httpx.Request("POST", url),
            json={
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {"content": json.dumps(result())},
                    }
                ]
            },
        )

    monkeypatch.setattr(verifier.httpx, "post", post)
    output = verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])
    assert output["status"] == "supported"
    assert calls[0][0] == "https://openrouter.ai/api/v1/chat/completions"
    body = calls[0][1]["json"]
    assert body["provider"] == {"require_parameters": True, "data_collection": "deny"}
    assert body["reasoning"] == {"effort": "low", "exclude": True}
    assert body["response_format"]["json_schema"]["strict"] is True


def test_openrouter_credit_or_provider_denial_abstains(client, monkeypatch):
    enable_ai(monkeypatch)
    monkeypatch.setattr(config, "AI_PROVIDER", "openrouter")

    def post(url, **kwargs):
        return httpx.Response(
            403,
            request=httpx.Request("POST", url),
            json={"error": "Key limit exceeded"},
        )

    monkeypatch.setattr(verifier.httpx, "post", post)
    output = verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])
    assert output["status"] == "abstained"
    assert output["findings"] == []
