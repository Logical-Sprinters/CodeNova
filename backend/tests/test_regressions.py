"""Submission blockers: edited checks, stale decisions, receipts and permissions."""

from concurrent.futures import ThreadPoolExecutor
import json

import pytest

from app import auth, config
from app.approval import store as approvals
from app.audit import store as audits
from app.receipts import store as receipts
from app.rules_store import store as rules

CREATOR = {"X-User-Id": "u1"}
REVIEWER = {"X-User-Id": "u2"}


def create(client, content="TODO: review this Acme offer", headers=None):
    response = client.post(
        "/api/v1/brand/check",
        headers=headers or CREATOR,
        json={"brand_name": "Acme", "content": content},
    )
    assert response.status_code == 200, response.text
    return response.json()


def edit(client, check_id, content, **extra):
    return client.post(
        f"/api/v1/brand/{check_id}/versions",
        headers=CREATOR,
        json={"content": content, **extra},
    )


def approve(client, check_id, **extra):
    return client.patch(
        f"/api/v1/reviews/{check_id}/decision",
        headers=REVIEWER,
        json={"decision": "approved", "note": "Reviewed exact content", **extra},
    )


def receipt(client, receipt_id, headers=None):
    response = client.get(f"/api/v1/receipts/{receipt_id}", headers=headers or CREATOR)
    assert response.status_code == 200, response.text
    return response.json()


def add_other_creator():
    users = json.loads(auth.USERS_FILE.read_text())
    users.append({"user_id": "u3", "name": "Other creator", "role": "creator"})
    auth.USERS_FILE.write_text(json.dumps(users))
    return {"X-User-Id": "u3"}


def change_rules():
    data = rules.load_rule_store()
    data["brands"]["acme"]["current_version"] = "2.0.0"
    data["brands"]["acme"]["versions"]["2.0.0"] = {
        "rules": [
            {
                "id": "ACME-NEW",
                "pattern": r"\blimited\b",
                "severity": "review",
                "message": "New rule matched",
                "suggestion": "Check the new offer rule",
            }
        ]
    }
    rules.RULES_FILE.write_text(json.dumps(data))


@pytest.mark.parametrize("content", ["", " ", "\n\t"])
def test_blank_checks_are_rejected(client, content):
    assert (
        client.post(
            "/api/v1/brand/check",
            headers=CREATOR,
            json={"brand_name": "Acme", "content": content},
        ).status_code
        == 422
    )
    assert approvals.load_records() == []
    assert receipts.load_receipts() == []


@pytest.mark.parametrize("brand", ["", "\t "])
def test_blank_brand_is_rejected(client, brand):
    assert (
        client.post(
            "/api/v1/brand/check",
            headers=CREATOR,
            json={"brand_name": brand, "content": "A message"},
        ).status_code
        == 422
    )


@pytest.mark.parametrize("content", ["", "  ", "\n\t"])
def test_blank_edits_do_not_destroy_an_approval(client, content):
    check = create(client)
    assert approve(client, check["check_id"]).status_code == 200
    assert edit(client, check["check_id"], content).status_code == 422
    assert approvals.get_record(check["check_id"])["status"] == "approved"
    assert len(receipts.load_receipts()) == 1


def test_edit_reruns_checks_and_clears_old_decision(client):
    check = create(client)
    assert approve(client, check["check_id"]).status_code == 200
    clean = edit(client, check["check_id"], "A factual product announcement.")
    assert clean.status_code == 200
    assert clean.json()["total_findings"] == 0
    assert clean.json()["scan_status"] == "passed"
    assert clean.json()["review_status"] == "pending"
    record = approvals.get_record(check["check_id"])
    assert all(
        record[field] is None for field in ("reviewer", "review_note", "decided_at")
    )
    assert record["content_version"] == 2
    assert record["versions"][0]["status"] == "approved"
    assert [version["version"] for version in record["versions"]] == [1, 2]
    edited = edit(client, check["check_id"], "Our plan is free forever and 100% safe.")
    assert edited.status_code == 200
    assert {finding["rule_id"] for finding in edited.json()["findings"]} == {
        "ACME-001",
        "BG-002",
    }
    assert edited.json()["content_version"] == 3
    record = approvals.get_record(check["check_id"])
    assert record["findings"] == edited.json()["findings"]
    last_receipt = receipt(client, edited.json()["receipt_id"])
    assert last_receipt["deterministic_findings"] == 2
    assert last_receipt["ai_verification"]["status"] == "abstained"


def test_only_owner_may_edit(client):
    other = add_other_creator()
    check = create(client)
    for headers in (REVIEWER, other):
        response = client.post(
            f"/api/v1/brand/{check['check_id']}/versions",
            headers=headers,
            json={"content": "An unauthorized edit"},
        )
        assert response.status_code == 403
    assert approvals.get_record(check["check_id"])["content_version"] == 1
    assert len(receipts.load_receipts()) == 1


def test_clean_scan_is_pending_and_can_receive_human_approval(client):
    check = create(client, "A factual product announcement.")
    assert check["scan_status"] == "passed"
    assert check["review_status"] == "pending"
    assert check["status"] == "review_required"
    pending = client.get("/api/v1/reviews?status=pending", headers=CREATOR).json()
    assert pending["total"] == 1
    assert approve(client, check["check_id"], expected_version=1).status_code == 200
    assert receipt(client, check["receipt_id"])["approval_valid"] is True


def test_stale_rules_block_decision_and_resubmission_uses_new_rules(client):
    check = create(client)
    change_rules()
    assert approve(client, check["check_id"]).status_code == 409
    result = edit(client, check["check_id"], "A limited offer.")
    assert result.status_code == 200
    assert result.json()["rules_version"] == "2.0.0"
    assert [finding["rule_id"] for finding in result.json()["findings"]] == ["ACME-NEW"]
    assert approve(client, check["check_id"], expected_version=2).status_code == 200
    assert receipt(client, result.json()["receipt_id"])["approval_valid"] is True


def test_receipt_status_and_superseded_approval_are_consistent(client):
    check = create(client)
    initial = receipt(client, check["receipt_id"])
    assert initial["final_status"] == "pending" and initial["approval_valid"] is False
    assert approve(client, check["check_id"]).status_code == 200
    approved = receipt(client, check["receipt_id"])
    assert approved["final_status"] == "approved" and approved["approval_valid"] is True
    assert approved["reviewer"] == "u2"
    result = edit(client, check["check_id"], "Updated factual text.").json()
    old = receipt(client, check["receipt_id"])
    assert old["is_current_version"] is False and old["approval_valid"] is False
    assert (
        old["final_status"] == "approved"
    )  # Historical outcome, not current approval.
    current = receipt(client, result["receipt_id"])
    assert (
        current["is_current_version"] is True and current["final_status"] == "pending"
    )
    assert approve(client, check["check_id"]).status_code == 200
    assert receipt(client, result["receipt_id"])["approval_valid"] is True
    change_rules()
    assert receipt(client, result["receipt_id"])["approval_valid"] is False


def test_auth_is_required_for_receipts_verification_and_audit(client):
    check = create(client)
    assert client.get("/api/v1/receipts/").status_code == 401
    assert client.get(f"/api/v1/receipts/{check['receipt_id']}").status_code == 401
    assert client.get("/api/v1/audit").status_code == 401
    assert (
        client.post(
            "/api/v1/approvals/verify",
            json={
                "check_id": check["check_id"],
                "brand_name": "Acme",
                "content": "TODO",
            },
        ).status_code
        == 401
    )


def test_creator_cannot_read_other_creators_content_or_receipt(client):
    other = add_other_creator()
    own = create(client)
    foreign = create(client, headers=other)
    assert client.get("/api/v1/reviews", headers=CREATOR).json()["total"] == 1
    assert client.get("/api/v1/reviews", headers=other).json()["total"] == 1
    assert client.get("/api/v1/reviews", headers=REVIEWER).json()["total"] == 2
    assert client.get("/api/v1/receipts/", headers=CREATOR).json()["total"] == 1
    assert (
        client.get(
            f"/api/v1/receipts/{foreign['receipt_id']}", headers=CREATOR
        ).status_code
        == 403
    )
    denied = client.post(
        "/api/v1/approvals/verify",
        headers=CREATOR,
        json={
            "check_id": foreign["check_id"],
            "brand_name": "Acme",
            "content": "TODO",
        },
    )
    assert denied.status_code == 403
    events = client.get("/api/v1/audit", headers=CREATOR).json()["events"]
    assert events and {event["check_id"] for event in events} == {own["check_id"]}


def test_stale_version_decision_or_edit_cannot_overwrite_new_content(client):
    check = create(client)
    assert (
        edit(client, check["check_id"], "New draft", expected_version=1).status_code
        == 200
    )
    assert approve(client, check["check_id"], expected_version=1).status_code == 409
    assert (
        edit(client, check["check_id"], "Old draft", expected_version=1).status_code
        == 409
    )
    assert approvals.get_record(check["check_id"])["content"] == "New draft"
    assert approve(client, check["check_id"], expected_version=2).status_code == 200


def test_verification_is_audited_and_preserves_exact_text(client):
    text = "  A factual message.\n"
    check = create(client, text)
    assert approve(client, check["check_id"]).status_code == 200
    for content, expected in [(text, True), (text.strip(), False)]:
        result = client.post(
            "/api/v1/approvals/verify",
            headers=CREATOR,
            json={
                "check_id": check["check_id"],
                "brand_name": " acme ",
                "content": content,
            },
        )
        assert result.status_code == 200 and result.json()["valid"] is expected
    verifications = [e for e in audits.load_audit() if e["action"] == "verify_approval"]
    assert [e["details"]["valid"] for e in verifications] == [True, False]


def test_concurrent_checks_do_not_lose_records_in_single_worker(client):
    with ThreadPoolExecutor(max_workers=5) as executor:
        results = list(
            executor.map(
                lambda i: create(client, f"TODO: concurrent draft {i}"), range(15)
            )
        )
    assert len({result["check_id"] for result in results}) == 15
    assert (
        len(approvals.load_records())
        == len(receipts.load_receipts())
        == len(audits.load_audit())
        == 15
    )


def test_only_one_concurrent_decision_is_accepted(client):
    check = create(client)
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(
            executor.map(lambda _: approve(client, check["check_id"]), range(2))
        )
    assert sorted(result.status_code for result in results) == [200, 409]


def test_corrupt_json_fails_clearly_instead_of_silently_resetting(client):
    approvals.STORE_FILE.write_text("not valid json")
    response = client.get("/api/v1/reviews", headers=CREATOR)
    assert response.status_code == 500 and "backup" in response.json()["detail"]
    assert approvals.STORE_FILE.read_text() == "not valid json"


def test_new_data_directory_is_initialized_without_resetting_existing_data(
    tmp_path, monkeypatch
):
    fresh = tmp_path / "fresh" / "data"
    monkeypatch.setattr(config, "DATA_DIR", fresh)
    config.initialize_data_store()
    assert (fresh / "users.json").is_file() and (fresh / "brand_rules.json").is_file()
    records = fresh / "review_records.json"
    records.write_text('[{"preserve":true}]')
    config.initialize_data_store()
    assert json.loads(records.read_text()) == [{"preserve": True}]


def test_invalid_status_and_unsupported_content_type_are_rejected(client):
    assert (
        client.get("/api/v1/reviews?status=anything", headers=CREATOR).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/brand/check",
            headers=CREATOR,
            json={
                "brand_name": "Acme",
                "content": "A message",
                "content_type": "image",
            },
        ).status_code
        == 422
    )
