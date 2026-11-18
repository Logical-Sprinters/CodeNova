"""Phase 2 tests: conflict escalation (10/10 abstain), coded overrides + clarity tickets, tamper lock, and shift-left preflight."""

import hashlib
import json

import pytest

from app.approval.store import load_records, load_seals
from app.audit.store import load_audit
from app.checks.conflicts import load_conflicts
from app.receipts.store import load_receipts
from app.rules_store import store as rule_store
from app.storage import read_json
from app import config


def _seed_rule(client, reviewer, *, rule_id, topic_key, canonical_value, pattern, rule_text, channels=None, owner_id=None):
    payload = {
        "rule_id": rule_id,
        "title": f"Rule {rule_id}",
        "brand_name": "Acme",
        "pattern": pattern,
        "description": rule_text,
        "rule_text": rule_text,
        "severity": "review",
        "topic_key": topic_key,
        "canonical_value": canonical_value,
        "effective_from": "2026-01-01T00:00:00Z",
        "channels": channels or ["all"],
    }
    if owner_id:
        payload["owner_id"] = owner_id
    res = client.post("/api/v1/library/rules", headers=reviewer, json=payload)
    assert res.status_code == 201, res.text
    return res.json()


def _seed_fact(client, reviewer, *, title, topic_key, canonical_value, content, channels=None):
    res = client.post(
        "/api/v1/library/facts",
        headers=reviewer,
        json={
            "title": title,
            "brand_name": "Acme",
            "content": content,
            "verified": True,
            "topic_key": topic_key,
            "canonical_value": canonical_value,
            "effective_from": "2026-01-01T00:00:00Z",
            "channels": channels or ["all"],
        },
    )
    assert res.status_code == 201, res.text
    return res.json()


@pytest.mark.parametrize("case_idx", range(10))
def test_ten_conflict_cases_all_abstain_and_pause_review(client, headers, case_idx):
    creator, reviewer = headers["creator"], headers["reviewer"]
    topic = f"topic_case_{case_idx}"
    mode = case_idx % 3
    if mode == 0:
        # Rule vs Rule conflict
        _seed_rule(
            client,
            reviewer,
            rule_id=f"CONF-R1-{case_idx}",
            topic_key=topic,
            canonical_value="0_fee",
            pattern=r"\bfee\b",
            rule_text=f"Transfer fee for case {case_idx} is ₹0.",
        )
        _seed_rule(
            client,
            reviewer,
            rule_id=f"CONF-R2-{case_idx}",
            topic_key=topic,
            canonical_value="25_inr",
            pattern=r"\btransfer\b",
            rule_text=f"Transfer fee for case {case_idx} is ₹25.",
        )
    elif mode == 1:
        # Fact vs Fact conflict
        _seed_fact(
            client,
            reviewer,
            title=f"Marketing Fact {case_idx}",
            topic_key=topic,
            canonical_value="free_tier",
            content=f"Campaign {case_idx} guarantees a permanent free tier.",
        )
        _seed_fact(
            client,
            reviewer,
            title=f"Legal Fact {case_idx}",
            topic_key=topic,
            canonical_value="paid_only",
            content=f"Legal schedule {case_idx} sets a paid-only minimum.",
        )
    else:
        # Rule vs Fact conflict
        _seed_rule(
            client,
            reviewer,
            rule_id=f"CONF-RF-{case_idx}",
            topic_key=topic,
            canonical_value="7_days",
            pattern=r"\brefund\b",
            rule_text=f"Refund window policy {case_idx} is 7 days.",
        )
        _seed_fact(
            client,
            reviewer,
            title=f"Legal Refund {case_idx}",
            topic_key=topic,
            canonical_value="30_days",
            content=f"Statutory refund window {case_idx} is 30 days.",
        )

    res = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": f"Draft copy referencing transfer fee and refund for case {case_idx}.",
            "check_at": "2026-10-15T12:00:00Z",
        },
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "review_paused_conflict"
    assert body["scan_status"] == "abstained_conflict"
    assert body["review_status"] == "paused_conflict"
    assert body["findings"] == []
    assert body["conflict_id"]
    assert len(body["conflicts"]) == 1
    assert len(body["conflicts"][0]["clauses"]) == 2


def test_conflict_gate_blocks_approval_until_admin_resolves_and_pins_winner(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    _seed_rule(
        client,
        reviewer,
        rule_id="FEE-ZERO",
        topic_key="transfer_fee",
        canonical_value="0_inr",
        pattern=r"\btransfer fee\b",
        rule_text="Marketing playbook: advertise ₹0 transfer fee.",
    )
    legal_fact = _seed_fact(
        client,
        reviewer,
        title="Legal Fee Schedule Nov 2026",
        topic_key="transfer_fee",
        canonical_value="25_inr",
        content="Legal schedule: ₹25 transfer fee applies across all accounts.",
    )

    # Pre-flight is stateless even when a conflict exists -> returns conflict_detected with 0 writes.
    preflight_conflict = client.post(
        "/api/v1/brand/preflight",
        headers=creator,
        json={"brand_name": "Acme", "content": "Enjoy zero transfer fee today!"},
    )
    assert preflight_conflict.status_code == 200
    assert preflight_conflict.json()["status"] == "conflict_detected"
    assert len(preflight_conflict.json()["conflicts"]) == 1
    assert load_conflicts() == []

    paused = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Enjoy zero transfer fee today! TODO: verify banner.",
            "check_at": "2026-11-10T10:00:00Z",
        },
    ).json()
    cid = paused["check_id"]
    conflict_id = paused["conflict_id"]
    assert paused["status"] == "review_paused_conflict"
    assert client.get("/api/v1/analytics", headers=creator).json()["paused_conflict"] == 1
    assert client.get("/api/v1/conflicts?status=open", headers=creator).json()["total"] == 1

    # Approval is blocked while paused on conflict.
    assert (
        client.patch(
            f"/api/v1/reviews/{cid}/decision",
            headers=reviewer,
            json={"decision": "approved"},
        ).status_code
        == 409
    )

    # Creator cannot resolve conflicts.
    assert (
        client.post(
            f"/api/v1/conflicts/{conflict_id}/resolve",
            headers=creator,
            json={
                "winning_source_type": "fact",
                "winning_source_id": legal_fact["id"],
            },
        ).status_code
        == 403
    )

    # Reviewer pins legal fact as winning source -> unlocks and re-scans check cleanly.
    resolved = client.post(
        f"/api/v1/conflicts/{conflict_id}/resolve",
        headers=reviewer,
        json={
            "winning_source_type": "fact",
            "winning_source_id": legal_fact["id"],
            "resolution_note": "Legal fee schedule overrides marketing playbook.",
        },
    )
    assert resolved.status_code == 200, resolved.text
    r_data = resolved.json()
    assert r_data["conflict"]["status"] == "resolved"
    assert r_data["updated_checks"][0]["check_id"] == cid
    assert r_data["updated_checks"][0]["status"] == "pending"

    # Subsequent review approval succeeds cleanly.
    approved = client.patch(
        f"/api/v1/reviews/{cid}/decision",
        headers=reviewer,
        json={"decision": "approved", "note": "Approved after conflict resolution."},
    )
    assert approved.status_code == 200, approved.text


def test_overrides_require_coded_reason_and_open_clarity_tickets_without_mutating_rules(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    rules_hash_before = hashlib.sha256(
        json.dumps(rule_store.load_rule_store(), sort_keys=True).encode()
    ).hexdigest()

    created_checks = []
    for idx in range(3):
        ch = client.post(
            "/api/v1/brand/check",
            headers=creator,
            json={
                "brand_name": "Acme",
                "content": f"Campaign {idx}: Our Acme plan is free forever.",
                "channel": "instagram",
            },
        ).json()
        created_checks.append(ch)

    first_cid = created_checks[0]["check_id"]
    first_fid = created_checks[0]["findings"][0]["finding_id"]

    # Missing or uncoded reason fails with 422.
    assert (
        client.post(
            f"/api/v1/reviews/{first_cid}/findings/{first_fid}/override",
            headers=reviewer,
            json={"note": "Looks fine to me"},
        ).status_code
        == 422
    )
    assert (
        client.post(
            f"/api/v1/reviews/{first_cid}/findings/{first_fid}/override",
            headers=reviewer,
            json={"reason_code": "CUSTOM_FREE_TEXT", "note": "Nope"},
        ).status_code
        == 422
    )
    # Creator cannot override.
    assert (
        client.post(
            f"/api/v1/reviews/{first_cid}/findings/{first_fid}/override",
            headers=creator,
            json={"reason_code": "AMBIGUOUS_RULE_TEXT", "note": "Creator try"},
        ).status_code
        == 403
    )

    # First two overrides do not open a ticket yet (default threshold = 3).
    for i in range(2):
        cid = created_checks[i]["check_id"]
        fid = created_checks[i]["findings"][0]["finding_id"]
        ov = client.post(
            f"/api/v1/reviews/{cid}/findings/{fid}/override",
            headers=reviewer,
            json={"reason_code": "AMBIGUOUS_RULE_TEXT", "note": f"Ambiguous edge case {i}"},
        )
        assert ov.status_code == 200, ov.text
        assert ov.json()["clarity_ticket"] is None
        assert ov.json()["rules_mutated"] is False

    # Duplicate override on same finding+version fails with 409.
    assert (
        client.post(
            f"/api/v1/reviews/{first_cid}/findings/{first_fid}/override",
            headers=reviewer,
            json={"reason_code": "FALSE_POSITIVE", "note": "Duplicate"},
        ).status_code
        == 409
    )

    # Third override on ACME-001 + instagram triggers Clarity Ticket for rule owner.
    third_cid = created_checks[2]["check_id"]
    third_fid = created_checks[2]["findings"][0]["finding_id"]
    ov3 = client.post(
        f"/api/v1/reviews/{third_cid}/findings/{third_fid}/override",
        headers=reviewer,
        json={"reason_code": "CONTEXTUAL_QUALIFIER", "note": "Footnote clarifies lifetime terms"},
    )
    assert ov3.status_code == 200, ov3.text
    ticket = ov3.json()["clarity_ticket"]
    assert ticket is not None
    assert ticket["rule_id"] == "ACME-001"
    assert ticket["rule_version"] == "1.0.0"
    assert ticket["channel"] == "instagram"
    assert ticket["override_count"] == 3
    assert ticket["status"] == "open"
    assert ticket["auto_mutated_rule"] is False
    assert ticket["reason_breakdown"] == {
        "AMBIGUOUS_RULE_TEXT": 2,
        "CONTEXTUAL_QUALIFIER": 1,
    }

    # Review queue reflects override metadata.
    reviews = client.get("/api/v1/reviews", headers=reviewer).json()["reviews"]
    assert any(
        f.get("overridden") is True and f["override"]["reason_code"] == "AMBIGUOUS_RULE_TEXT"
        for r in reviews
        for f in r["findings"]
    )

    # Clarity ticket lifecycle update works without mutating rules.
    tickets = client.get("/api/v1/clarity-tickets", headers=reviewer).json()
    assert tickets["total"] == 1
    patched = client.patch(
        f"/api/v1/clarity-tickets/{ticket['ticket_id']}",
        headers=reviewer,
        json={"status": "acknowledged", "resolution_note": "Scheduled wording review"},
    )
    assert patched.status_code == 200
    assert patched.json()["ticket"]["status"] == "acknowledged"

    # Cross-channel friction (instagram + email + web on BG-002) also aggregates into a multi-channel Clarity Ticket.
    multi_channels = ["instagram", "email", "web"]
    for idx, ch_name in enumerate(multi_channels):
        mc = client.post(
            "/api/v1/brand/check",
            headers=creator,
            json={
                "brand_name": "Acme",
                "content": f"Cross-channel test {idx}: 100% safe service.",
                "channel": ch_name,
            },
        ).json()
        bg_finding = next(f for f in mc["findings"] if f["rule_id"] == "BG-002")
        ov_multi = client.post(
            f"/api/v1/reviews/{mc['check_id']}/findings/{bg_finding['finding_id']}/override",
            headers=reviewer,
            json={"reason_code": "CHANNEL_EXEMPTION", "note": f"Channel {ch_name} footnote applies"},
        )
        assert ov_multi.status_code == 200, ov_multi.text
        if idx == 2:
            t_multi = ov_multi.json()["clarity_ticket"]
            assert t_multi is not None
            assert t_multi["rule_id"] == "BG-002"
            assert t_multi["channel"] == "multi"
            assert set(t_multi["channels_affected"]) == {"instagram", "email", "web"}

    assert client.get("/api/v1/overrides?rule_id=BG-002", headers=reviewer).json()["total"] == 3

    # Hard invariant: brand_rules remained 100% untouched.
    rules_hash_after = hashlib.sha256(
        json.dumps(rule_store.load_rule_store(), sort_keys=True).encode()
    ).hexdigest()
    assert rules_hash_before == rules_hash_after


def test_single_comma_tamper_voids_seal_and_returns_exact_word_diff(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    approved_text = "Savings earn up to 8%, terms apply."
    check = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": approved_text},
    ).json()
    cid = check["check_id"]
    dec = client.patch(
        f"/api/v1/reviews/{cid}/decision",
        headers=reviewer,
        json={"decision": "approved", "note": "Exact punctuation verified"},
    )
    assert dec.status_code == 200, dec.text

    seals = load_seals()
    assert len(seals) == 1
    seal_snapshot = dict(seals[0])

    # Exact verification -> SEALED
    sealed_res = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={"check_id": cid, "brand_name": "Acme", "content": approved_text},
    ).json()
    assert sealed_res["valid"] is True
    assert sealed_res["seal_status"] == "SEALED"
    assert sealed_res["approved_hash"] == sealed_res["submitted_hash"]

    # Single-comma tamper -> VOIDED_TAMPERED with exact comma diff
    comma_tampered = "Savings earn up to 8% terms apply."
    voided = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={"check_id": cid, "brand_name": "Acme", "content": comma_tampered},
    ).json()
    assert voided["valid"] is False
    assert voided["seal_status"] == "VOIDED_TAMPERED"
    assert voided["approved_hash"] != voided["submitted_hash"]
    assert any(
        t["op"] == "delete" and t["approved_text"] == ","
        for t in voided["tampered_tokens"]
    )

    # Word replacement tamper -> isolated word diff
    word_tampered = "Savings earn guaranteed 8%, terms apply."
    voided_word = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={"check_id": cid, "brand_name": "Acme", "content": word_tampered},
    ).json()
    assert voided_word["valid"] is False
    assert voided_word["seal_status"] == "VOIDED_TAMPERED"
    assert any(
        t["approved_text"] == "up to" and t["current_text"] == "guaranteed"
        for t in voided_word["tampered_tokens"]
    )

    # Multipart upload verification also detects single-comma tamper.
    upload_res = client.post(
        "/api/v1/approvals/verify-upload",
        headers=creator,
        data={"check_id": cid, "brand_name": "Acme"},
        files={"file": ("copy.txt", comma_tampered.encode("utf-8"), "text/plain")},
    ).json()
    assert upload_res["valid"] is False
    assert upload_res["seal_status"] == "VOIDED_TAMPERED"

    # Seal stays immutable and tamper_detected details were logged on verify_approval.
    assert load_seals()[0] == seal_snapshot
    assert any(
        e["action"] == "verify_approval" and e["details"].get("tamper_detected") is True
        for e in load_audit()
    )


def test_shift_left_preflight_catches_rule_and_fact_issues_without_db_writes(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    _seed_fact(
        client,
        reviewer,
        title="Standard Savings Yield Policy",
        topic_key="savings_yield",
        canonical_value="6.5_pct",
        content="Standard Savings offers up to 6.5% APY on qualifying deposits.",
    )

    # Pre-flight detects COMP-14 + BG-002 + numeric mismatch against verified fact, with 0 DB writes.
    preflight = client.post(
        "/api/v1/brand/preflight",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Enjoy guaranteed 12% returns on Standard Savings.",
        },
    )
    assert preflight.status_code == 200, preflight.text
    pf = preflight.json()
    assert pf["status"] == "warnings_detected"
    rule_ids = {f["rule_id"] for f in pf["findings"]}
    assert "COMP-14" in rule_ids
    assert any(rid.startswith("AI-FACT-") for rid in rule_ids)
    comp = next(f for f in pf["findings"] if f["rule_id"] == "COMP-14")
    assert comp["replacement"] == "projected up to"
    fact_finding = next(f for f in pf["findings"] if f["rule_id"].startswith("AI-FACT-"))
    assert fact_finding["evidence"] == "12%"
    assert fact_finding["replacement"] == "6.5%"
    assert fact_finding["rule_quote"] in "Standard Savings offers up to 6.5% APY on qualifying deposits."

    # Verify statelessness: zero records, receipts, conflicts, notifications, or audit logs written!
    assert load_records() == []
    assert load_receipts() == []
    assert load_conflicts() == []
    assert read_json(config.DATA_DIR / "notifications.json", []) == []
    assert not any(
        e["action"] in {"create_check", "preflight"} for e in load_audit()
    )
