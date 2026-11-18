"""Phase 1 tests: auth/preferences bug fixes, strict grounding drop gate, and point-in-time rules."""

from fastapi.testclient import TestClient

from app.approval.store import load_records, save_records
from app.checks.grounding import filter_grounded_findings
from app.checks.llm.verifier import retrieve_facts
from app.main import app
from app.rules_store.store import resolve_active_rules


def test_auth_profile_and_preferences_persist_across_restarts(client, headers):
    creator = headers["creator"]
    prefs = client.get("/api/v1/auth/preferences", headers=creator)
    assert prefs.status_code == 200
    assert prefs.json() == {
        "email_updates": True,
        "review_activity": True,
        "product_news": False,
    }

    saved = client.put(
        "/api/v1/auth/preferences",
        headers=creator,
        json={"email_updates": False, "product_news": True},
    )
    assert saved.status_code == 200
    assert saved.json() == {
        "email_updates": False,
        "review_activity": True,
        "product_news": True,
    }

    bad_name = client.patch(
        "/api/v1/auth/profile", headers=creator, json={"name": " "}
    )
    assert bad_name.status_code == 422

    updated = client.patch(
        "/api/v1/auth/profile", headers=creator, json={"name": "Alice Updated"}
    )
    assert updated.status_code == 200
    assert updated.json()["message"] == "Display name updated"
    assert updated.json()["user"]["name"] == "Alice Updated"
    assert client.get("/api/v1/auth/me", headers=creator).json()["user"]["name"] == "Alice Updated"

    with TestClient(app) as reopened:
        assert reopened.get("/api/v1/auth/me", headers=creator).json()["user"]["name"] == "Alice Updated"
        assert reopened.get("/api/v1/auth/preferences", headers=creator).json() == {
            "email_updates": False,
            "review_activity": True,
            "product_news": True,
        }


def test_grounding_gate_drops_invented_paraphrased_and_stale_findings(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    content = "Our Acme plan is free forever."
    scan = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": content, "check_at": "2026-10-01T12:00:00Z"},
    )
    assert scan.status_code == 200, scan.text
    data = scan.json()
    assert data["total_findings"] == 1
    valid_finding = data["findings"][0]
    assert valid_finding["rule_id"] == "ACME-001"
    assert valid_finding["rule_version"] == "1.0.0"
    assert valid_finding["rule_quote"] in (
        "Promotional copy must not promise permanent free access using phrases like free forever unless explicitly backed by a currently approved lifetime offer."
    )

    fact = client.post(
        "/api/v1/library/facts",
        headers=reviewer,
        json={
            "title": "Acme Uptime SLA",
            "brand_name": "Acme",
            "content": "Acme Enterprise includes a 99.95% uptime SLA in standard contracts.",
            "verified": True,
            "effective_from": "2026-01-01T00:00:00Z",
        },
    ).json()

    active_rules, _ = resolve_active_rules("Acme", check_at="2026-10-01T12:00:00Z")
    valid_ai_finding = {
        "finding_id": "ai-fact-valid",
        "rule_id": "AI-FACT-001",
        "rule_version": "1.0.0",
        "rule_quote": "99.95% uptime SLA",
        "rule_quote_start": fact["content"].index("99.95% uptime SLA"),
        "rule_quote_end": fact["content"].index("99.95% uptime SLA") + len("99.95% uptime SLA"),
        "severity": "review",
        "message": "Claim conflicts with verified SLA",
        "evidence": "free forever",
        "start_index": content.index("free forever"),
        "end_index": content.index("free forever") + len("free forever"),
        "source_origin": "caption",
        "citations": [{"fact_id": fact["id"], "quote": "99.95% uptime SLA"}],
    }

    bad_findings = [
        valid_finding | {"rule_id": "INVENTED-999"},
        valid_finding | {"rule_quote": "paraphrased quote not in rule text"},
        valid_finding | {"rule_version": "0.9.0"},
        valid_finding | {"start_index": 0, "end_index": 3, "evidence": "free forever"},
        valid_finding | {"rule_quote_start": 0, "rule_quote_end": 5},
        valid_finding | {"source_origin": "visual"},
        valid_ai_finding | {"rule_version": "2.0.0"},
        valid_ai_finding | {"rule_quote": "nearly 100% uptime guarantee"},
        valid_ai_finding | {"citations": [{"fact_id": "nonexistent", "quote": "99.95% uptime SLA"}]},
    ]
    grounded, dropped = filter_grounded_findings(
        [valid_finding, valid_ai_finding] + bad_findings,
        active_rules,
        content,
        active_facts=[fact],
    )
    assert len(grounded) == 2
    assert len(dropped) == len(bad_findings)

    # Integration test: inject ungrounded findings into stored review record and ensure GET /reviews drops them server-side.
    records = load_records()
    records[0]["findings"].extend(bad_findings)
    save_records(records)

    res = client.get("/api/v1/reviews", headers=reviewer)
    assert res.status_code == 200
    review = res.json()["reviews"][0]
    assert len(review["findings"]) == 1
    assert review["findings"][0]["rule_id"] == "ACME-001"
    assert review["grounding_reverified"] is True
    assert review["dropped_ungrounded_count"] == len(bad_findings)


def test_point_in_time_rules_produce_three_distinct_verdicts_across_windows(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]

    # Reject invalid time window and non-verbatim rule_quote at rule creation time.
    assert (
        client.post(
            "/api/v1/library/rules",
            headers=reviewer,
            json={
                "rule_id": "ACME-BAD-WIN",
                "title": "Bad Window",
                "brand_name": "Acme",
                "pattern": r"\bbad\b",
                "rule_text": "Avoid bad words.",
                "effective_from": "2026-07-01T00:00:00Z",
                "expires_at": "2026-04-01T00:00:00Z",
            },
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/library/rules",
            headers=reviewer,
            json={
                "rule_id": "ACME-BAD-QUOTE",
                "title": "Bad Quote",
                "brand_name": "Acme",
                "pattern": r"\bbad\b",
                "rule_text": "Avoid bad words.",
                "rule_quote": "completely paraphrased sentence",
            },
        ).status_code
        == 422
    )

    seasonal = client.post(
        "/api/v1/library/rules",
        headers=reviewer,
        json={
            "rule_id": "ACME-Q2-PROMO",
            "title": "Q2 Promo Cap",
            "brand_name": "Acme",
            "pattern": r"\bspring bonus\b",
            "description": "Spring bonus offer restricted during Q2 transition.",
            "rule_text": "During Q2 2026, marketing copy must not promote spring bonus without finance sign-off.",
            "rule_quote": "must not promote spring bonus without finance sign-off",
            "severity": "review",
            "effective_from": "2026-04-01T00:00:00Z",
            "expires_at": "2026-07-01T00:00:00Z",
        },
    )
    assert seasonal.status_code == 201, seasonal.text

    old_summer = client.post(
        "/api/v1/library/rules",
        headers=reviewer,
        json={
            "rule_id": "ACME-OLD-PHRASE",
            "title": "Old Early Access Wording",
            "brand_name": "Acme",
            "pattern": r"\bearly bird\b",
            "description": "Legacy early bird rule.",
            "rule_text": "Legacy campaigns must avoid early bird terminology.",
            "severity": "warning",
            "effective_from": "2026-01-01T00:00:00Z",
        },
    )
    assert old_summer.status_code == 201, old_summer.text

    new_post_q2 = client.post(
        "/api/v1/library/rules",
        headers=reviewer,
        json={
            "rule_id": "ACME-POST-Q2",
            "title": "Post-Q2 Launch Rule",
            "brand_name": "Acme",
            "pattern": r"\bsummer launch\b",
            "description": "Post-Q2 launch rule supersedes legacy early bird wording.",
            "rule_text": "From July 1, 2026 onward, summer launch phrasing requires legal disclosure.",
            "rule_quote": "summer launch phrasing requires legal disclosure",
            "severity": "critical",
            "effective_from": "2026-07-01T00:00:00Z",
            "supersedes": "ACME-OLD-PHRASE",
        },
    )
    assert new_post_q2.status_code == 201, new_post_q2.text

    copy = "Join our early bird spring bonus and summer launch campaign."

    before = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": copy, "check_at": "2026-03-15T12:00:00Z"},
    ).json()
    during = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": copy, "check_at": "2026-05-15T12:00:00Z"},
    ).json()
    after = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": copy, "check_at": "2026-07-01T00:00:00Z"},
    ).json()

    assert {f["rule_id"] for f in before["findings"]} == {"ACME-OLD-PHRASE"}
    assert {f["rule_id"] for f in during["findings"]} == {"ACME-OLD-PHRASE", "ACME-Q2-PROMO"}
    # At exact expires_at (half-open), ACME-Q2-PROMO expires; ACME-POST-Q2 activates & supersedes ACME-OLD-PHRASE.
    assert {f["rule_id"] for f in after["findings"]} == {"ACME-POST-Q2"}

    # Library & brand endpoints support as_of filtering.
    q2_rules = client.get(
        "/api/v1/library/rules?brand_name=Acme&as_of=2026-05-15T12:00:00Z",
        headers=creator,
    ).json()["items"]
    assert {r["id"] for r in q2_rules} >= {"ACME-OLD-PHRASE", "ACME-Q2-PROMO"}
    assert "ACME-POST-Q2" not in {r["id"] for r in q2_rules}


def test_point_in_time_facts_and_channels(client, headers):
    reviewer = headers["reviewer"]
    f1 = client.post(
        "/api/v1/library/facts",
        headers=reviewer,
        json={
            "title": "Pricing 2025",
            "brand_name": "Acme",
            "content": "Acme Pro costs $49 per month.",
            "verified": True,
            "effective_from": "2025-01-01T00:00:00Z",
            "channels": ["web"],
        },
    ).json()
    f2 = client.post(
        "/api/v1/library/facts",
        headers=reviewer,
        json={
            "title": "Pricing 2026",
            "brand_name": "Acme",
            "content": "Acme Pro costs $59 per month.",
            "verified": True,
            "effective_from": "2026-06-01T00:00:00Z",
            "supersedes": f1["id"],
            "channels": ["web"],
        },
    ).json()

    before = retrieve_facts("Acme Pro costs dollars", "Acme", check_at="2026-05-01T00:00:00Z", channel="web")
    after = retrieve_facts("Acme Pro costs dollars", "Acme", check_at="2026-06-02T00:00:00Z", channel="web")
    wrong_channel = retrieve_facts("Acme Pro costs dollars", "Acme", check_at="2026-06-02T00:00:00Z", channel="email")

    assert [f["id"] for f in before] == [f1["id"]]
    assert [f["id"] for f in after] == [f2["id"]]
    assert wrong_channel == []


def test_approval_verification_and_receipt_name_changed_or_expired_rule(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    client.post(
        "/api/v1/library/rules",
        headers=reviewer,
        json={
            "rule_id": "ACME-EXP-01",
            "title": "Year-end Rule",
            "brand_name": "Acme",
            "pattern": r"\bholiday deal\b",
            "description": "Restricted phrase before Dec.",
            "rule_text": "Holiday deal requires disclaimer prior to December.",
            "severity": "warning",
            "effective_from": "2026-10-01T00:00:00Z",
            "expires_at": "2026-12-01T00:00:00Z",
        },
    )

    content = "Clean approved copy."
    check = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={"brand_name": "Acme", "content": content, "check_at": "2026-11-15T00:00:00Z"},
    ).json()
    cid = check["check_id"]
    rid = check["receipt_id"]
    assert client.patch(
        f"/api/v1/reviews/{cid}/decision",
        headers=reviewer,
        json={"decision": "approved"},
    ).status_code == 200

    ok = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={
            "check_id": cid,
            "brand_name": "Acme",
            "content": content,
            "verify_at": "2026-11-15T00:00:00Z",
        },
    ).json()
    assert ok["valid"] is True
    assert ok["seal_status"] == "SEALED"

    expired_verify = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={
            "check_id": cid,
            "brand_name": "Acme",
            "content": content,
            "verify_at": "2026-12-05T00:00:00Z",
        },
    ).json()
    assert expired_verify["valid"] is False
    assert expired_verify["seal_status"] == "INVALIDATED_RULE_CHANGE"
    assert any(
        c["rule_id"] == "ACME-EXP-01" and c["change_type"] == "expired"
        for c in expired_verify["rule_changes"]
    )

    edit_res = client.put(
        "/api/v1/library/rules/ACME-001",
        headers=reviewer,
        json={
            "title": "Restricted Phrase Revised",
            "brand_name": "Acme",
            "pattern": r"\bfree forever\b",
            "description": "Updated restricted phrase rule.",
            "rule_text": "Promotional copy must not promise permanent free access using phrases like free forever without VP approval.",
            "severity": "critical",
        },
    )
    assert edit_res.status_code == 200
    assert edit_res.json()["version"] == "1.0.1"

    changed_verify = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={
            "check_id": cid,
            "brand_name": "Acme",
            "content": content,
            "verify_at": "2026-11-15T00:00:00Z",
        },
    ).json()
    assert changed_verify["valid"] is False
    assert "ACME-001" in changed_verify["reason"]
    assert any(
        c["rule_id"] == "ACME-001"
        and c["change_type"] == "modified"
        and c["old_version"] == "1.0.0"
        and c["new_version"] == "1.0.1"
        for c in changed_verify["rule_changes"]
    )

    receipt = client.get(f"/api/v1/receipts/{rid}", headers=creator).json()
    assert receipt["rules_current"] is False
    assert any(c["rule_id"] == "ACME-001" for c in receipt["rule_changes"])
