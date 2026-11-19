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
    monkeypatch.setattr(config, "AI_BASE_URL", "https://api.openai.com/v1")
    monkeypatch.setattr(config, "AI_MODEL", "gpt-5.4-mini")
    monkeypatch.setattr(config, "AI_DATA_COLLECTION", "")


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


def test_openrouter_free_model_omits_deny_and_supports_json_fallback(client, monkeypatch):
    enable_ai(monkeypatch)
    monkeypatch.setattr(config, "AI_PROVIDER", "openrouter")
    monkeypatch.setattr(config, "AI_MODEL", "nvidia/nemotron-3-super-120b-a12b:free")
    monkeypatch.setattr(config, "AI_BASE_URL", "https://openrouter.ai/api/v1")
    monkeypatch.setattr(config, "AI_DATA_COLLECTION", "")
    calls = []

    def post(url, **kwargs):
        calls.append(kwargs["json"])
        if len(calls) == 1:
            return httpx.Response(
                404,
                request=httpx.Request("POST", url),
                json={"error": "No endpoints found that can handle the requested parameters"},
            )
        return httpx.Response(
            200,
            request=httpx.Request("POST", url),
            json={
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {"content": f"```json\n{json.dumps(result())}\n```"},
                    }
                ]
            },
        )

    monkeypatch.setattr(verifier.httpx, "post", post)
    output = verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])
    assert output["status"] == "supported"
    assert len(calls) == 2
    assert calls[0]["provider"] == {"require_parameters": True}
    assert "data_collection" not in calls[0]["provider"]
    assert calls[1]["response_format"] == {"type": "json_object"}


def test_gemini_openai_compat_omits_store_and_uses_max_tokens(client, monkeypatch):
    enable_ai(monkeypatch)
    monkeypatch.setattr(config, "AI_PROVIDER", "gemini")
    monkeypatch.setattr(config, "AI_MODEL", "gemini-2.5-flash")
    monkeypatch.setattr(
        config,
        "AI_BASE_URL",
        "https://generativelanguage.googleapis.com/v1beta/openai",
    )
    calls = []

    def post(url, **kwargs):
        calls.append((url, kwargs["json"]))
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
    assert calls[0][0] == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    body = calls[0][1]
    assert "store" not in body
    assert "reasoning_effort" not in body
    assert body["max_tokens"] == 3000
    assert body["response_format"]["type"] == "json_schema"

    login = client.post(
        "/api/v1/auth/login",
        json={"email": "creator@brandguard.demo", "password": "Demo@12345"},
    )
    token = login.json()["access_token"]
    status = client.get(
        "/api/v1/system/status",
        headers={"Authorization": f"Bearer {token}"},
    ).json()
    assert status["ai_configured"] is True
    assert status["ai_provider"] == "gemini"


def test_paraphrased_draft_still_retrieves_active_verified_brand_facts(client, monkeypatch):
    enable_ai(monkeypatch)
    # Zero word overlap with FACT ("Acme costs 49 dollars per month.")
    passages = verifier.retrieve_facts(
        "Flagship plan just nine bucks weekly",
        brand_name="Acme",
        facts=[FACT],
    )
    assert len(passages) == 1
    assert passages[0]["id"] == "fact-one"

    # Unverified fact yields a clear guidance message instead of calling LLM
    monkeypatch.setattr(
        verifier.httpx, "post", lambda *a, **k: pytest.fail("Unexpected provider call")
    )
    out = verifier.run_ai_verification(
        "Flagship plan",
        brand_name="Acme",
        brand_facts=[FACT | {"verified": False}],
    )
    assert out["status"] == "abstained"
    assert "none are verified" in out["message"]


def test_gemini_404_falls_back_to_active_flash_model_and_reports_friendly_message(
    client, monkeypatch
):
    enable_ai(monkeypatch)
    monkeypatch.setattr(config, "AI_PROVIDER", "gemini")
    monkeypatch.setattr(config, "AI_MODEL", "gemini-2.5-flash")
    monkeypatch.setattr(
        config,
        "AI_BASE_URL",
        "https://generativelanguage.googleapis.com/v1beta/openai",
    )
    tried_models = []

    def post(url, **kwargs):
        model = kwargs["json"]["model"]
        tried_models.append(model)
        if model == "gemini-2.5-flash":
            return httpx.Response(
                404,
                request=httpx.Request("POST", url),
                json={"error": "Model not found"},
            )
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
    assert output["model"] == "gemini-3.5-flash-lite"
    assert tried_models == ["gemini-2.5-flash", "gemini-3.5-flash-lite"]

    def always_404(url, **kwargs):
        return httpx.Response(
            404,
            request=httpx.Request("POST", url),
            json={"error": "Not found"},
        )

    monkeypatch.setattr(verifier.httpx, "post", always_404)
    abstained = verifier.run_ai_verification("Acme costs 49 dollars", brand_facts=[FACT])
    assert abstained["status"] == "abstained"
    assert "standard brand rule checks still ran" in abstained["message"].lower()
    assert "gemini-2.5-flash" in abstained["message"]
    assert "HTTP 404" not in abstained["message"]


def test_reviewer_notifications_do_not_duplicate_v1_and_v2_for_same_check(
    client, headers
):
    creator, reviewer = headers["creator"], headers["reviewer"]
    created = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": "Draft v1 text"},
    )
    assert created.status_code == 200
    cid = created.json()["check_id"]

    rev_before = client.get("/api/v1/notifications", headers=reviewer).json()
    assert rev_before["total"] == 1
    assert "submission awaits review" in rev_before["items"][0]["body"]

    edited = client.post(
        f"/api/v1/brand/{cid}/versions",
        headers=creator,
        json={"content": "Draft v2 text", "expected_version": 1},
    )
    assert edited.status_code == 200

    rev_after = client.get("/api/v1/notifications", headers=reviewer).json()
    assert rev_after["total"] == 1
    assert rev_after["unread"] == 1
    assert "(rev 2) awaits review" in rev_after["items"][0]["body"]

    decided = client.patch(
        f"/api/v1/reviews/{cid}/decision",
        headers=reviewer,
        json={"decision": "approved", "expected_version": 2},
    )
    assert decided.status_code == 200
    assert client.get("/api/v1/notifications", headers=reviewer).json()["unread"] == 0


def test_request_changes_allows_creator_resubmission_and_tracks_analytics(
    client, headers
):
    creator, reviewer = headers["creator"], headers["reviewer"]
    created = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": "Initial draft claim"},
    )
    assert created.status_code == 200
    cid = created.json()["check_id"]

    req_changes = client.patch(
        f"/api/v1/reviews/{cid}/decision",
        headers=reviewer,
        json={
            "decision": "changes_requested",
            "note": "Clarify billing cadence",
            "expected_version": 1,
        },
    )
    assert req_changes.status_code == 200
    assert req_changes.json()["review"]["status"] == "changes_requested"
    assert req_changes.json()["review"]["review_note"] == "Clarify billing cadence"

    analytics = client.get("/api/v1/analytics", headers=creator).json()
    assert analytics["changes_requested"] == 1
    assert analytics["rejected"] == 0

    creator_notes = client.get("/api/v1/notifications", headers=creator).json()
    assert creator_notes["unread"] == 1
    assert "Clarify billing cadence" in creator_notes["items"][0]["body"]

    resubmitted = client.post(
        f"/api/v1/brand/{cid}/versions",
        headers=creator,
        json={"content": "Monthly billing is 49 dollars.", "expected_version": 1},
    )
    assert resubmitted.status_code == 200
    assert resubmitted.json()["review_status"] == "pending"
    assert resubmitted.json()["content_version"] == 2

    approved = client.patch(
        f"/api/v1/reviews/{cid}/decision",
        headers=reviewer,
        json={"decision": "approved", "expected_version": 2},
    )
    assert approved.status_code == 200
    assert approved.json()["review"]["status"] == "approved"


def test_two_step_inspect_then_submit_and_newest_first_creator_metadata(
    client, headers
):
    creator, reviewer = headers["creator"], headers["reviewer"]

    first = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": "Older submitted copy"},
    )
    assert first.status_code == 200

    drafted = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Newest inspected draft copy",
            "submit_for_review": False,
        },
    )
    assert drafted.status_code == 200
    assert drafted.json()["review_status"] == "draft"
    draft_cid = drafted.json()["check_id"]

    # Unsubmitted inspection draft is NOT in the review queue yet.
    queue_before = client.get("/api/v1/reviews", headers=reviewer).json()
    assert [r["check_id"] for r in queue_before["reviews"]] == [
        first.json()["check_id"]
    ]
    assert client.get("/api/v1/analytics", headers=creator).json()["pending"] == 1

    # Explicit submit transitions draft -> pending and puts newest check at the TOP.
    submitted = client.post(
        f"/api/v1/brand/{draft_cid}/submit",
        headers=creator,
    )
    assert submitted.status_code == 200
    assert submitted.json()["review_status"] == "pending"

    queue_after = client.get("/api/v1/reviews", headers=reviewer).json()
    assert [r["check_id"] for r in queue_after["reviews"]] == [
        draft_cid,
        first.json()["check_id"],
    ]
    newest = queue_after["reviews"][0]
    assert newest["creator_name"] == "Alice"
    assert newest["creator_email"] == "creator@brandguard.demo"


def test_revising_approved_check_creates_linked_new_check_without_breaking_seal(
    client, headers
):
    creator, reviewer = headers["creator"], headers["reviewer"]

    original = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": "Approved launch announcement."},
    ).json()
    orig_id = original["check_id"]

    decided = client.patch(
        f"/api/v1/reviews/{orig_id}/decision",
        headers=reviewer,
        json={"decision": "approved", "note": "Looks compliant"},
    )
    assert decided.status_code == 200

    # Derive a new check from the approved submission.
    derived_draft = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Amended launch announcement for November.",
            "submit_for_review": False,
            "parent_check_id": orig_id,
        },
    )
    assert derived_draft.status_code == 200
    derived_data = derived_draft.json()
    assert derived_data["check_id"] != orig_id
    assert derived_data["parent_check_id"] == orig_id
    assert derived_data["review_status"] == "draft"

    submitted = client.post(
        f"/api/v1/brand/{derived_data['check_id']}/submit",
        headers=creator,
    )
    assert submitted.status_code == 200
    assert submitted.json()["review_status"] == "pending"
    assert submitted.json()["parent_check_id"] == orig_id

    # Original approved check and its cryptographic seal remain untouched & valid.
    verify_orig = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={
            "check_id": orig_id,
            "brand_name": "Acme",
            "content": "Approved launch announcement.",
        },
    )
    assert verify_orig.status_code == 200
    assert verify_orig.json()["valid"] is True

