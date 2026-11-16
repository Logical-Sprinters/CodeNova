from app import config, auth_service


def test_local_password_change_requires_current_password_and_revokes_sessions(
    client, headers
):
    h = headers["creator"]
    assert (
        client.put(
            "/api/v1/auth/password", headers=h, json={"password": "ChangedPass123!"}
        ).status_code
        == 403
    )
    assert (
        client.put(
            "/api/v1/auth/password",
            headers=h,
            json={"password": "ChangedPass123!", "current_password": "wrong"},
        ).status_code
        == 403
    )
    changed = client.put(
        "/api/v1/auth/password",
        headers=h,
        json={"password": "ChangedPass123!", "current_password": "Demo@12345"},
    )
    assert changed.status_code == 200, changed.text
    assert client.get("/api/v1/auth/me", headers=h).status_code == 401
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "creator@brandguard.demo", "password": "ChangedPass123!"},
    )
    assert login.status_code == 200
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"email": "creator@brandguard.demo", "password": "Demo@12345"},
        ).status_code
        == 401
    )


def test_recovery_form_is_self_contained_and_auth_responses_are_not_cached(
    client, headers
):
    page = client.get("/auth/reset")
    assert page.status_code == 200
    assert page.headers["cache-control"] == "no-store"
    assert "location.hash" in page.text
    assert "history.replaceState" in page.text
    assert "localStorage" not in page.text
    assert (
        client.get("/api/v1/auth/me", headers=headers["creator"]).headers[
            "cache-control"
        ]
        == "no-store"
    )


def test_cloud_recovery_requires_explicit_safe_redirect(client, monkeypatch):
    monkeypatch.setattr(config, "AUTH_PROVIDER", "supabase")
    monkeypatch.setattr(config, "AUTH_REDIRECT_URL", "")
    response = client.post("/api/v1/auth/recover", json={"email": "person@example.com"})
    assert response.status_code == 503
    monkeypatch.setattr(
        config, "AUTH_REDIRECT_URL", "https://api.example.com/auth/reset"
    )
    calls = []
    monkeypatch.setattr(
        auth_service, "supabase_request", lambda *a, **k: calls.append((a, k)) or {}
    )
    assert (
        client.post(
            "/api/v1/auth/recover", json={"email": "person@example.com"}
        ).status_code
        == 200
    )
    assert "redirect_to=https%3A%2F%2Fapi.example.com%2Fauth%2Freset" in calls[0][0][1]
