"""Regression coverage for the supported local demo API workflow.

This is not a production security certification. See docs/PROJECT_GUIDE.md.
"""

import json

import pytest

from app.approval import store as approval_store
from app.audit import store as audit_store
from app.receipts import store as receipt_store
from app.rules_store import store as rule_store

CONTENT = "Our Acme plan is free forever. TODO: confirm offer details."


def create_check(client, headers, content=CONTENT, brand="Acme"):
    response = client.post(
        "/api/v1/brand/check",
        json={"brand_name": brand, "content": content, "content_type": "text"},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    return response.json()


def decide(client, check_id, headers, decision="approved"):
    return client.patch(
        f"/api/v1/reviews/{check_id}/decision",
        json={"decision": decision, "note": "Demo review"},
        headers=headers,
    )


def verify(client, check_id, content=CONTENT, brand="Acme"):
    response = client.post(
        "/api/v1/approvals/verify",
        json={"check_id": check_id, "brand_name": brand, "content": content},
        headers={"X-User-Id": "u1"},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_health_and_routes(client):
    assert client.get("/").json()["status"] == "running"
    assert client.get("/health").json()["status"] == "healthy"
    assert "/api/v1/brand/check" in client.get("/openapi.json").json()["paths"]


@pytest.mark.parametrize("headers", [{}, {"X-User-Id": "unknown"}])
def test_missing_or_unknown_user_cannot_create_or_list(client, headers):
    assert client.get("/api/v1/reviews", headers=headers).status_code == 401
    response = client.post(
        "/api/v1/brand/check",
        json={"brand_name": "Acme", "content": CONTENT},
        headers=headers,
    )
    assert response.status_code == 401
    assert approval_store.load_records() == []


def test_known_rules_and_unknown_brand(client):
    response = client.get("/api/v1/brand/rules/Acme")
    assert response.status_code == 200
    assert response.json()["current_version"] == "1.0.0"
    assert client.get("/api/v1/brand/rules/no-such-brand").status_code == 404


def test_check_findings_receipt_and_queue(client, creator_headers):
    result = create_check(client, creator_headers)
    assert result["status"] == "review_required"
    assert result["total_findings"] == len(result["findings"]) == 2
    assert {finding["rule_id"] for finding in result["findings"]} == {
        "ACME-001",
        "BG-001",
    }
    for finding in result["findings"]:
        assert (
            CONTENT[finding["start_index"] : finding["end_index"]]
            == finding["evidence"]
        )

    queue = client.get(
        "/api/v1/reviews", params={"status": "pending"}, headers=creator_headers
    ).json()
    assert queue["total"] == 1
    assert queue["reviews"][0]["creator_id"] == "u1"
    receipt = client.get(
        f"/api/v1/receipts/{result['receipt_id']}", headers=creator_headers
    ).json()
    assert receipt["check_id"] == result["check_id"]
    assert receipt["ai_verification"]["status"] == "abstained"
    assert receipt["rules_version"] == "1.0.0"
    assert client.get("/api/v1/receipts/", headers=creator_headers).json()["total"] == 1


def test_creator_cannot_escalate_role_with_a_header(client, creator_headers):
    result = create_check(client, creator_headers)
    response = decide(
        client, result["check_id"], {**creator_headers, "X-User-Role": "reviewer"}
    )
    assert response.status_code == 403
    assert approval_store.get_record(result["check_id"])["status"] == "pending"


def test_reviewer_cannot_approve_own_submission(client, reviewer_headers):
    result = create_check(client, reviewer_headers)
    assert decide(client, result["check_id"], reviewer_headers).status_code == 409


@pytest.mark.parametrize("decision", ["approved", "rejected"])
def test_reviewer_can_decide_pending_content(
    client, creator_headers, reviewer_headers, decision
):
    result = create_check(client, creator_headers)
    response = decide(client, result["check_id"], reviewer_headers, decision)
    assert response.status_code == 200
    record = response.json()["review"]
    assert record["status"] == decision
    assert record["reviewer"] == "u2"
    assert record["review_note"] == "Demo review"
    assert verify(client, result["check_id"])["valid"] is (decision == "approved")
    assert decide(client, result["check_id"], reviewer_headers).status_code == 409


def test_approval_requires_exact_content_brand_and_rules(
    client, creator_headers, reviewer_headers
):
    result = create_check(client, creator_headers)
    check_id = result["check_id"]
    assert decide(client, check_id, reviewer_headers).status_code == 200
    assert verify(client, check_id)["valid"] is True
    assert verify(client, check_id, content=CONTENT + " changed")["valid"] is False
    assert verify(client, check_id, brand="Other")["valid"] is False
    rules = rule_store.load_rule_store()
    rules["brands"]["acme"]["current_version"] = "2.0.0"
    rule_store.RULES_FILE.write_text(json.dumps(rules), encoding="utf-8")
    assert verify(client, check_id)["valid"] is False



def test_trusted_source_conflict_is_visible_and_blocks_approval(
    client, creator_headers, reviewer_headers
):
    common = {
        "title": "Canada availability",
        "brand_name": "Acme",
        "category": "Product Claims",
        "enabled": True,
    }
    positive = client.post(
        "/api/v1/library/guidelines",
        json={**common, "content": "Acme is available in Canada."},
        headers=reviewer_headers,
    )
    negative = client.post(
        "/api/v1/library/guidelines",
        json={**common, "content": "Acme is not available in Canada."},
        headers=reviewer_headers,
    )
    assert positive.status_code == 201, positive.text
    assert negative.status_code == 201, negative.text

    result = create_check(client, creator_headers, content="A product announcement.")
    check_id = result["check_id"]

    queue = client.get("/api/v1/reviews", headers=reviewer_headers)
    assert queue.status_code == 200, queue.text
    review = next(r for r in queue.json()["reviews"] if r["check_id"] == check_id)
    assert review["source_conflicts"]
    assert len(review["source_conflicts"][0]["evidence"]) == 2

    blocked = decide(client, check_id, reviewer_headers, "approved")
    assert blocked.status_code == 409
    assert "source_conflicts" in blocked.json()["detail"]
    assert approval_store.get_record(check_id)["status"] == "pending"

    rejected = decide(client, check_id, reviewer_headers, "rejected")
    assert rejected.status_code == 200

def test_approval_fingerprint_is_saved_and_detects_metadata_tampering(
    client, creator_headers, reviewer_headers
):
    result = create_check(client, creator_headers)
    check_id = result["check_id"]
    approved = decide(client, check_id, reviewer_headers)
    assert approved.status_code == 200, approved.text

    record = approval_store.get_record(check_id)
    fingerprint = record.get("approval_fingerprint")
    assert fingerprint
    assert len(fingerprint) == 64
    assert record["approval_fingerprint_algorithm"] == "SHA-256"
    assert record["versions"][-1]["approval_fingerprint"] == fingerprint

    receipt = receipt_store.get_receipt(record["receipt_id"])
    assert receipt["approval_fingerprint"] == fingerprint
    assert verify(client, check_id)["valid"] is True

    records = approval_store.load_records()
    stored = next(row for row in records if row["check_id"] == check_id)
    stored["reviewer"] = "tampered-reviewer"
    approval_store.save_records(records)
    checked = verify(client, check_id)
    assert checked["valid"] is False
    assert "fingerprint mismatch" in checked["reason"].lower()


def test_resubmission_clears_active_fingerprint_but_preserves_old_snapshot(
    client, creator_headers, reviewer_headers
):
    result = create_check(client, creator_headers)
    check_id = result["check_id"]
    assert decide(client, check_id, reviewer_headers).status_code == 200
    approved_record = approval_store.get_record(check_id)
    old_fingerprint = approved_record["approval_fingerprint"]

    edited = "Updated demo offer. TODO: legal review."
    response = client.post(
        f"/api/v1/brand/{check_id}/versions",
        json={"content": edited},
        headers=creator_headers,
    )
    assert response.status_code == 200
    updated = approval_store.get_record(check_id)
    assert updated["status"] == "pending"
    assert updated["approval_fingerprint"] is None
    assert updated["versions"][-2]["approval_fingerprint"] == old_fingerprint
    assert verify(client, check_id, content=edited)["valid"] is False


def test_legacy_approval_without_fingerprint_fails_closed(
    client, creator_headers, reviewer_headers
):
    result = create_check(client, creator_headers)
    check_id = result["check_id"]
    assert decide(client, check_id, reviewer_headers).status_code == 200

    records = approval_store.load_records()
    stored = next(row for row in records if row["check_id"] == check_id)
    stored.pop("approval_fingerprint", None)
    stored.pop("approval_fingerprint_algorithm", None)
    approval_store.save_records(records)

    checked = verify(client, check_id)
    assert checked["valid"] is False
    assert "no approval-time" in checked["reason"].lower()


def test_version_resets_approval_and_writes_separate_audit_and_receipt(
    client, creator_headers, reviewer_headers
):
    result = create_check(client, creator_headers)
    check_id = result["check_id"]
    assert decide(client, check_id, reviewer_headers).status_code == 200
    edited = "Updated demo offer. TODO: legal review."
    response = client.post(
        f"/api/v1/brand/{check_id}/versions",
        json={"content": edited},
        headers=creator_headers,
    )
    assert response.status_code == 200
    version = response.json()
    assert version["check_id"] == check_id
    assert version["receipt_id"] != result["receipt_id"]
    assert verify(client, check_id, content=edited)["valid"] is False
    assert approval_store.get_record(check_id)["status"] == "pending"
    assert len(receipt_store.load_receipts()) == 2
    audit = json.loads(audit_store.AUDIT_FILE.read_text(encoding="utf-8"))
    assert [
        entry["action"] for entry in audit if entry["action"] != "verify_approval"
    ] == [
        "create_check",
        "review_decision",
        "submit_version",
    ]


def test_invalid_decision_and_missing_records(
    client, creator_headers, reviewer_headers
):
    result = create_check(client, creator_headers)
    assert (
        decide(client, result["check_id"], reviewer_headers, "invalid").status_code
        == 400
    )
    assert decide(client, "missing", reviewer_headers).status_code == 404
    assert (
        client.get("/api/v1/receipts/missing", headers=creator_headers).status_code
        == 404
    )
    assert verify(client, "missing")["valid"] is False
    assert (
        client.post(
            "/api/v1/brand/missing/versions",
            json={"content": "Edited"},
            headers=creator_headers,
        ).status_code
        == 404
    )


def test_current_clean_text_response_and_empty_body_validation(client, creator_headers):
    result = create_check(
        client, creator_headers, content="A clear product announcement."
    )
    assert result["status"] == "review_required"
    assert result["scan_status"] == "passed"
    assert result["review_status"] == "pending"
    assert result["findings"] == []
    response = client.post(
        "/api/v1/brand/check",
        json={"brand_name": "Acme", "content": ""},
        headers=creator_headers,
    )
    assert response.status_code == 422


def test_store_paths_do_not_depend_on_current_working_directory(isolated_stores):
    assert approval_store.STORE_FILE.parent == isolated_stores
    assert receipt_store.RECEIPTS_FILE.parent == isolated_stores
    assert audit_store.AUDIT_FILE.parent == isolated_stores
    assert rule_store.RULES_FILE.parent == isolated_stores
    assert approval_store.load_records() == []
    assert "acme" in rule_store.load_rule_store()["brands"]

def test_source_conflict_detected_even_when_guideline_titles_differ(
    client, creator_headers, reviewer_headers
):
    common = {
        "brand_name": "Acme",
        "category": "Product Claims",
        "enabled": True,
    }

    positive = client.post(
        "/api/v1/library/guidelines",
        json={
            **common,
            "title": "International Product Availability",
            "content": "Acme is available in Canada.",
        },
        headers=reviewer_headers,
    )

    negative = client.post(
        "/api/v1/library/guidelines",
        json={
            **common,
            "title": "Regional Sales Restriction",
            "content": "Acme is not available in Canada.",
        },
        headers=reviewer_headers,
    )

    assert positive.status_code == 201, positive.text
    assert negative.status_code == 201, negative.text

    result = create_check(
        client, creator_headers, content="A product announcement."
    )

    queue = client.get("/api/v1/reviews", headers=reviewer_headers)
    assert queue.status_code == 200, queue.text

    review = next(
        item for item in queue.json()["reviews"]
        if item["check_id"] == result["check_id"]
    )

    assert review["source_conflicts"]
    assert len(review["source_conflicts"][0]["evidence"]) == 2

    blocked = decide(
        client, result["check_id"], reviewer_headers, "approved"
    )

    assert blocked.status_code == 409
    assert "source_conflicts" in blocked.json()["detail"]
