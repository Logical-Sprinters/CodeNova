"""Tests for time-boxed accidental review decision amendment & seal revocation."""

from datetime import datetime, timedelta, timezone

from app import config
from app.approval import store as approval_store
from app.audit import store as audit_store
from app.receipts import store as receipt_store

CONTENT = "Acme offers trusted clarity across campaigns."


def _submit_check(client, creator_headers, content=CONTENT):
    res = client.post(
        "/api/v1/brand/check",
        json={"brand_name": "Acme", "content": content, "content_type": "text"},
        headers=creator_headers,
    )
    assert res.status_code == 200, res.text
    return res.json()


def test_amend_accidental_reject_to_approve_within_window(
    client, creator_headers, reviewer_headers
):
    check = _submit_check(client, creator_headers)
    check_id = check["check_id"]

    reject_res = client.patch(
        f"/api/v1/reviews/{check_id}/decision",
        json={"decision": "rejected", "note": "Clicked wrong button"},
        headers=reviewer_headers,
    )
    assert reject_res.status_code == 200, reject_res.text
    assert reject_res.json()["review"]["can_amend"] is True
    assert reject_res.json()["review"]["amend_window_minutes"] == config.DECISION_AMEND_WINDOW_MINUTES

    # Duplicate /decision still returns 409 (must use explicit /amend endpoint).
    dup = client.patch(
        f"/api/v1/reviews/{check_id}/decision",
        json={"decision": "approved", "note": "Try overwrite"},
        headers=reviewer_headers,
    )
    assert dup.status_code == 409

    amend_res = client.post(
        f"/api/v1/reviews/{check_id}/amend",
        json={
            "decision": "approved",
            "reason": "Reversed accidental rejection after verifying copy",
            "expected_version": 1,
        },
        headers=reviewer_headers,
    )
    assert amend_res.status_code == 200, amend_res.text
    payload = amend_res.json()
    assert payload["previous_decision"] == "rejected"
    assert payload["review"]["status"] == "approved"
    assert payload["review"]["seal_id"]
    history = payload["review"]["decision_history"]
    assert [entry["decision"] for entry in history] == ["rejected", "approved"]
    assert [entry["kind"] for entry in history] == ["initial", "amended"]

    verify = client.post(
        "/api/v1/approvals/verify",
        json={"check_id": check_id, "brand_name": "Acme", "content": CONTENT},
        headers=creator_headers,
    )
    assert verify.status_code == 200
    assert verify.json()["valid"] is True
    assert verify.json()["seal_status"] == "SEALED"

    receipt = receipt_store.get_receipt(check["receipt_id"])
    assert receipt["final_status"] == "approved"
    assert len(receipt["decision_history"]) == 2

    audit_events = [e for e in audit_store.load_audit() if e.get("action") == "amend_decision"]
    assert len(audit_events) == 1
    assert audit_events[0]["details"]["previous_decision"] == "rejected"
    assert audit_events[0]["details"]["new_decision"] == "approved"


def test_amend_accidental_approve_revokes_seal_and_verifies_revoked(
    client, creator_headers, reviewer_headers
):
    check = _submit_check(client, creator_headers)
    check_id = check["check_id"]

    approve_res = client.patch(
        f"/api/v1/reviews/{check_id}/decision",
        json={"decision": "approved", "note": "Initial approval"},
        headers=reviewer_headers,
    )
    assert approve_res.status_code == 200, approve_res.text
    original_seal_id = approve_res.json()["review"]["seal_id"]
    assert original_seal_id

    amend_res = client.post(
        f"/api/v1/reviews/{check_id}/amend",
        json={
            "decision": "changes_requested",
            "reason": "Missed unverified metric claim on second pass",
            "expected_version": 1,
        },
        headers=reviewer_headers,
    )
    assert amend_res.status_code == 200, amend_res.text
    payload = amend_res.json()
    assert payload["previous_decision"] == "approved"
    assert payload["revoked_seal_id"] == original_seal_id
    assert payload["review"]["status"] == "changes_requested"
    assert payload["review"]["seal_id"] is None

    # Seal record stays in store marked revoked=True, never erased.
    seals = [s for s in approval_store.load_seals() if s["check_id"] == check_id]
    assert len(seals) == 1
    assert seals[0]["seal_id"] == original_seal_id
    assert seals[0]["revoked"] is True
    assert "Missed unverified metric" in seals[0]["revocation_reason"]

    verify = client.post(
        "/api/v1/approvals/verify",
        json={"check_id": check_id, "brand_name": "Acme", "content": CONTENT},
        headers=creator_headers,
    )
    assert verify.status_code == 200
    v_data = verify.json()
    assert v_data["valid"] is False
    assert v_data["seal_status"] == "REVOKED"
    assert "Missed unverified metric" in v_data["reason"]

    notifs_res = client.get("/api/v1/notifications", headers=creator_headers)
    assert notifs_res.status_code == 200
    notifs = notifs_res.json().get("items", notifs_res.json().get("notifications", []))
    assert any("revoked" in (n.get("title") or "").lower() for n in notifs)


def test_amend_window_expiry_blocks_amendment_and_repeated_amends_never_extend(
    client, creator_headers, reviewer_headers
):
    check = _submit_check(client, creator_headers)
    check_id = check["check_id"]

    assert (
        client.patch(
            f"/api/v1/reviews/{check_id}/decision",
            json={"decision": "rejected", "note": "Mistake"},
            headers=reviewer_headers,
        ).status_code
        == 200
    )

    # First amend within window succeeds.
    assert (
        client.post(
            f"/api/v1/reviews/{check_id}/amend",
            json={"decision": "approved", "reason": "Corrected promptly"},
            headers=reviewer_headers,
        ).status_code
        == 200
    )

    # Simulate initial_decided_at being past the grace period; decided_at stays recent,
    # proving repeated amends cannot extend the original anchor window.
    records = approval_store.load_records()
    expired_anchor = (
        datetime.now(timezone.utc)
        - timedelta(minutes=config.DECISION_AMEND_WINDOW_MINUTES + 2)
    ).isoformat()
    for rec in records:
        if rec["check_id"] == check_id:
            rec["initial_decided_at"] = expired_anchor
    approval_store.save_records(records)

    queue = client.get("/api/v1/reviews", headers=reviewer_headers).json()
    match = next(r for r in queue["reviews"] if r["check_id"] == check_id)
    assert match["can_amend"] is False
    assert match["amend_remaining_seconds"] == 0

    blocked = client.post(
        f"/api/v1/reviews/{check_id}/amend",
        json={"decision": "rejected", "reason": "Too late now"},
        headers=reviewer_headers,
    )
    assert blocked.status_code == 409
    assert "window expired" in blocked.json()["detail"].lower()


def test_amend_guards_self_amend_short_reason_rule_change_and_new_version_window(
    client, creator_headers, reviewer_headers
):
    check = _submit_check(client, creator_headers)
    check_id = check["check_id"]

    assert (
        client.patch(
            f"/api/v1/reviews/{check_id}/decision",
            json={"decision": "rejected", "note": "Needs update"},
            headers=reviewer_headers,
        ).status_code
        == 200
    )

    # Creator cannot amend their own submission.
    self_amend = client.post(
        f"/api/v1/reviews/{check_id}/amend",
        json={"decision": "approved", "reason": "Let me approve myself"},
        headers=creator_headers,
    )
    assert self_amend.status_code == 403  # creator role blocked first

    # Short/whitespace reason rejected by schema validation.
    short_reason = client.post(
        f"/api/v1/reviews/{check_id}/amend",
        json={"decision": "approved", "reason": "no"},
        headers=reviewer_headers,
    )
    assert short_reason.status_code == 422

    # Same status rejected.
    same = client.post(
        f"/api/v1/reviews/{check_id}/amend",
        json={"decision": "rejected", "reason": "Still rejected"},
        headers=reviewer_headers,
    )
    assert same.status_code == 400

    # Simulate window expired on v1, then creator submits v2 -> v2 gets fresh window!
    records = approval_store.load_records()
    for rec in records:
        if rec["check_id"] == check_id:
            rec["initial_decided_at"] = (
                datetime.now(timezone.utc) - timedelta(hours=3)
            ).isoformat()
    approval_store.save_records(records)

    v2 = client.post(
        f"/api/v1/brand/{check_id}/versions",
        json={
            "content": "Acme updated copy without issues.",
            "expected_version": 1,
            "submit_for_review": True,
        },
        headers=creator_headers,
    )
    assert v2.status_code == 200, v2.text

    v2_reject = client.patch(
        f"/api/v1/reviews/{check_id}/decision",
        json={"decision": "rejected", "note": "Accidental reject on v2"},
        headers=reviewer_headers,
    )
    assert v2_reject.status_code == 200
    assert v2_reject.json()["review"]["can_amend"] is True

    v2_amend = client.post(
        f"/api/v1/reviews/{check_id}/amend",
        json={
            "decision": "approved",
            "reason": "v2 fresh window works",
            "expected_version": 2,
        },
        headers=reviewer_headers,
    )
    assert v2_amend.status_code == 200, v2_amend.text
    assert v2_amend.json()["review"]["status"] == "approved"
