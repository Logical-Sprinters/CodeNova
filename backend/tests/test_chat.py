import json

from app import auth, config

CREATOR = {"X-User-Id": "u1"}
REVIEWER = {"X-User-Id": "u2"}


def test_chat_answers_from_verified_context_and_persists_history(client):
    (config.DATA_DIR / "library_guidelines.json").write_text(
        json.dumps(
            [
                {
                    "id": "guide-1",
                    "brand_name": "Acme",
                    "title": "Logo usage",
                    "content": "Use the approved Acme logo on a clear background.",
                    "enabled": True,
                    "approval_status": "active",
                }
            ]
        ),
        encoding="utf-8",
    )

    response = client.post(
        "/api/v1/chat",
        headers=CREATOR,
        json={"message": "What is the Acme logo guideline?", "language": "en"},
    )

    assert response.status_code == 200
    result = response.json()
    assert result["sources"][0]["id"] == "guide-1"
    assert "approved Acme logo" in result["message"]["answer"]
    conversation_id = result["conversation_id"]

    history = client.get(
        f"/api/v1/chat/conversations/{conversation_id}", headers=CREATOR
    )
    assert history.status_code == 200
    assert [message["sender"] for message in history.json()["messages"]] == [
        "user",
        "assistant",
    ]


def test_chat_history_is_private_and_suggestions_follow_authenticated_role(client):
    response = client.post(
        "/api/v1/chat",
        headers=CREATOR,
        json={"message": "Hello"},
    )
    assert response.status_code == 200
    conversation_id = response.json()["conversation_id"]

    assert (
        client.get(
            f"/api/v1/chat/conversations/{conversation_id}", headers=REVIEWER
        ).status_code
        == 404
    )
    assert client.get("/api/v1/chat/conversations", headers=REVIEWER).json()[
        "total"
    ] == 0
    assert "pending reviews" in client.get(
        "/api/v1/chat/suggestions", headers=REVIEWER
    ).json()["suggestions"][0].lower()


def test_creator_cannot_read_another_creators_campaign_context(client):
    users = json.loads(auth.USERS_FILE.read_text(encoding="utf-8"))
    users.append({"user_id": "u3", "name": "Other creator", "role": "creator"})
    auth.USERS_FILE.write_text(json.dumps(users), encoding="utf-8")
    other_creator = {"X-User-Id": "u3"}

    created = client.post(
        "/api/v1/brand/check",
        headers=CREATOR,
        json={"brand_name": "Acme", "content": "An offer for review."},
    )
    assert created.status_code == 200

    denied = client.post(
        "/api/v1/chat",
        headers=other_creator,
        json={
            "message": "Why was this rejected?",
            "context": {
                "type": "campaign",
                "id": created.json()["check_id"],
            },
        },
    )
    assert denied.status_code == 404


def test_campaign_context_list_contains_only_accessible_metadata(client):
    created = client.post(
        "/api/v1/brand/check",
        headers=CREATOR,
        json={"brand_name": "Acme", "content": "A private creator submission."},
    )
    assert created.status_code == 200
    check_id = created.json()["check_id"]

    creator_context = client.get("/api/v1/chat/context", headers=CREATOR).json()
    assert [item["id"] for item in creator_context["items"]] == [check_id]
    assert "content" not in creator_context["items"][0]

    reviewer_context = client.get("/api/v1/chat/context", headers=REVIEWER).json()
    assert [item["id"] for item in reviewer_context["items"]] == [check_id]


def test_history_rechecks_role_for_reviewer_only_sources(client):
    response = client.post(
        "/api/v1/chat",
        headers=REVIEWER,
        json={"message": "Summarize pending reviews"},
    )
    assert response.status_code == 200
    conversation_id = response.json()["conversation_id"]

    users = json.loads(auth.USERS_FILE.read_text(encoding="utf-8"))
    reviewer = next(item for item in users if item["user_id"] == "u2")
    reviewer["role"] = "creator"
    auth.USERS_FILE.write_text(json.dumps(users), encoding="utf-8")

    assert (
        client.get(
            f"/api/v1/chat/conversations/{conversation_id}", headers=REVIEWER
        ).status_code
        == 404
    )
    listed = client.get("/api/v1/chat/conversations", headers=REVIEWER).json()
    assert listed["total"] == 0


def test_configured_ai_provider_receives_server_role_and_language(monkeypatch, client):
    class ProviderResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {"choices": [{"message": {"content": "Namaste, I can help."}}]}

    def fake_post(url, headers, json, timeout):
        assert url.endswith("/chat/completions")
        assert headers["Authorization"] == "Bearer test-secret"
        assert "Hindi" in json["messages"][0]["content"]
        assert "creator" in json["messages"][0]["content"]
        return ProviderResponse()

    monkeypatch.setattr(config, "AI_PROVIDER", "openai")
    monkeypatch.setattr(config, "AI_API_KEY", "test-secret")
    monkeypatch.setattr(config, "AI_BASE_URL", "https://provider.test/v1")
    monkeypatch.setattr("app.routers.chat.httpx.post", fake_post)

    response = client.post(
        "/api/v1/chat",
        headers=CREATOR,
        json={"message": "Namaste", "language": "hi"},
    )

    assert response.status_code == 200
    assert response.json()["message"]["answer"] == "Namaste, I can help."
