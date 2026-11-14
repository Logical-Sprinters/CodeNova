"""Integration tests. They need a seeded database and skip cleanly without one:
    docker compose up -d && make db
"""
import os

import pytest

pytestmark = pytest.mark.skipif(
    not os.getenv("DATABASE_URL"),
    reason="DATABASE_URL not set; start the stack with `make up && make db`",
)

CREATOR = "00000000-0000-4000-8000-000000000002"
REVIEWER = "00000000-0000-4000-8000-000000000003"
DEACTIVATED = "00000000-0000-4000-8000-000000000004"

DEMO = ("Task Flow Pro is now just $29 per user and it is the #1 task app "
        "guaranteed to keep your team on track.")


def headers(user):
    return {"X-User-Id": user}


def test_health_reports_a_seeded_database(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["users"] >= 4
    assert body["live_rules_now"] >= 1


def test_identity_is_required(client):
    assert client.get("/content").status_code == 401


def test_a_deactivated_account_is_refused(client):
    assert client.get("/content", headers=headers(DEACTIVATED)).status_code == 403


def test_submitting_copy_returns_findings_with_spans(client):
    body = client.post("/content", headers=headers(CREATOR),
                       json={"text": DEMO, "channel": "social"}).json()
    findings = body["check"]["findings"]
    assert findings
    price = next(f for f in findings if f["rule_id"] == "PRIC-002")
    assert DEMO[price["span"][0]:price["span"][1]] == "$29"


def test_a_creator_cannot_approve(client):
    created = client.post("/content", headers=headers(CREATOR),
                          json={"text": DEMO, "channel": "social"}).json()
    response = client.post(f"/content/{created['content_id']}/approve",
                           headers=headers(CREATOR))
    assert response.status_code == 403


def test_approval_is_refused_while_a_confirmed_match_stands(client):
    created = client.post("/content", headers=headers(CREATOR),
                          json={"text": DEMO, "channel": "social"}).json()
    response = client.post(f"/content/{created['content_id']}/approve",
                           headers=headers(REVIEWER))
    assert response.status_code == 409
    assert "blocking" in str(response.json()["detail"]).lower()


def test_editing_after_approval_voids_it(client):
    created = client.post("/content", headers=headers(CREATOR),
                          json={"text": "TaskFlow keeps every team tidy.",
                                "channel": "email"}).json()
    content_id = created["content_id"]
    client.post(f"/content/{content_id}/approve", headers=headers(REVIEWER))
    edited = client.post(f"/content/{content_id}/versions", headers=headers(CREATOR),
                         json={"text": "TaskFlow keeps every single team tidy."}).json()
    assert edited["voided_approvals"] == 1

    ledger = client.get(f"/ledger?content_id={content_id}", headers=headers(CREATOR)).json()
    void_rows = [e for e in ledger if e["action"] == "voided"]
    assert void_rows and void_rows[0]["actor_type"] == "SYSTEM"
