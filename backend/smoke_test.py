"""Actual HTTP smoke test. Requires a running, ISOLATED local-demo backend.

python smoke_test.py --base-url http://127.0.0.1:8000
Never run against production: this deliberately creates users/content/files.
"""

import argparse
from uuid import uuid4
import httpx


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    checks = []
    with httpx.Client(base_url=args.base_url.rstrip("/"), timeout=45) as client:

        def call(label, method, path, expected=200, **kwargs):
            response = client.request(method, path, **kwargs)
            assert (
                response.status_code == expected
            ), f"{label}: expected {expected}, got {response.status_code}: {response.text[:300]}"
            checks.append(label)
            print(f"PASS {len(checks):02}: {label}", flush=True)
            return (
                response.json()
                if response.headers.get("content-type", "").startswith(
                    "application/json"
                )
                else response.content
            )

        call("health", "GET", "/health")
        cfg = call("local-demo safety gate", "GET", "/api/v1/auth/config")
        assert (
            cfg["auth_provider"] == "local" and cfg["demo_accounts_enabled"]
        ), "This smoke script only targets isolated seeded local demo mode."
        call(
            "legacy ID impersonation blocked",
            "GET",
            "/api/v1/reviews",
            401,
            headers={"X-User-Id": "u2"},
        )
        creator = call(
            "server creator login",
            "POST",
            "/api/v1/auth/login",
            json={"email": "creator@brandguard.demo", "password": "Demo@12345"},
        )
        reviewer = call(
            "server reviewer login",
            "POST",
            "/api/v1/auth/login",
            json={"email": "reviewer@brandguard.demo", "password": "Demo@12345"},
        )
        ch = {"Authorization": "Bearer " + creator["access_token"]}
        rh = {"Authorization": "Bearer " + reviewer["access_token"]}
        status = call("runtime config", "GET", "/api/v1/system/status", headers=ch)
        assert not status[
            "ai_configured"
        ], "Disable AI for this deterministic no-cost smoke script."
        suffix = uuid4().hex[:10]
        brand = "Smoke-" + suffix
        other = call(
            "public signup restricted to creator",
            "POST",
            "/api/v1/auth/signup",
            json={
                "email": f"smoke-{suffix}@example.com",
                "name": "Smoke User",
                "password": "OnlyForIsolatedSmoke123!",
            },
        )
        assert other["user"]["role"] == "creator"
        oh = {"Authorization": "Bearer " + other["access_token"]}
        asset = call(
            "real document upload/extraction",
            "POST",
            "/api/v1/files",
            201,
            headers=ch,
            files={
                "file": ("source.txt", b"Actual stored document text.", "text/plain")
            },
        )
        assert asset["extracted_text"] == "Actual stored document text."
        assert (
            call(
                "owner document download",
                "GET",
                f"/api/v1/files/{asset['id']}/download",
                headers=ch,
            )
            == b"Actual stored document text."
        )
        call(
            "other creator cannot download file",
            "GET",
            f"/api/v1/files/{asset['id']}/download",
            403,
            headers=oh,
        )
        draft_body = {
            "title": "HTTP draft",
            "brand_name": brand,
            "content": "TODO prohibitedphrase",
            "attachments": [{"id": asset["id"], "name": asset["name"]}],
        }
        draft = call(
            "durable draft with real attachment",
            "POST",
            "/api/v1/drafts",
            201,
            headers=ch,
            json=draft_body,
        )
        call(
            "draft revision update",
            "PUT",
            f"/api/v1/drafts/{draft['id']}",
            headers=ch,
            json=draft_body | {"expected_revision": 1},
        )
        call(
            "stale draft rejected",
            "PUT",
            f"/api/v1/drafts/{draft['id']}",
            409,
            headers=ch,
            json=draft_body | {"expected_revision": 1},
        )
        call(
            "other creator draft protection",
            "PUT",
            f"/api/v1/drafts/{draft['id']}",
            404,
            headers=oh,
            json=draft_body,
        )
        rule_body = {
            "title": "Smoke rule",
            "brand_name": brand,
            "pattern": "prohibitedphrase",
            "description": "Smoke evidence finding",
        }
        call(
            "creator cannot mutate shared rules",
            "POST",
            "/api/v1/library/rules",
            403,
            headers=ch,
            json=rule_body,
        )
        rule = call(
            "reviewer creates enforceable rule",
            "POST",
            "/api/v1/library/rules",
            201,
            headers=rh,
            json=rule_body,
        )
        first = call(
            "scan uses new backend rule",
            "POST",
            "/api/v1/brand/check",
            headers=ch,
            json={"brand_name": brand, "content": draft_body["content"]},
        )
        assert rule["id"] in [f["rule_id"] for f in first["findings"]]
        assert first["ai_verification"]["status"] == "abstained"
        cid = first["check_id"]
        call(
            "private receipt protected",
            "GET",
            "/api/v1/receipts/" + first["receipt_id"],
            403,
            headers=oh,
        )
        call(
            "creator cannot approve",
            "PATCH",
            f"/api/v1/reviews/{cid}/decision",
            403,
            headers=ch,
            json={"decision": "approved"},
        )
        call(
            "independent reviewer approval",
            "PATCH",
            f"/api/v1/reviews/{cid}/decision",
            headers=rh,
            json={"decision": "approved", "expected_version": 1},
        )
        verified = call(
            "exact-content approval verification",
            "POST",
            "/api/v1/approvals/verify",
            headers=ch,
            json={
                "check_id": cid,
                "brand_name": brand,
                "content": draft_body["content"],
            },
        )
        assert verified["valid"]
        changed = call(
            "owner edit reruns scan and clears approval",
            "POST",
            f"/api/v1/brand/{cid}/versions",
            headers=ch,
            json={"content": "Final content", "expected_version": 1},
        )
        assert (
            changed["content_version"] == 2
            and changed["review_status"] == "pending"
            and changed["total_findings"] == 0
        )
        call(
            "stale review rejected",
            "PATCH",
            f"/api/v1/reviews/{cid}/decision",
            409,
            headers=rh,
            json={"decision": "approved", "expected_version": 1},
        )
        old_receipt = call(
            "old receipt is no longer approval-valid",
            "GET",
            "/api/v1/receipts/" + first["receipt_id"],
            headers=ch,
        )
        assert old_receipt["approval_valid"] is False
        activity = call("live analytics", "GET", "/api/v1/analytics", headers=ch)
        assert activity["total_checks"] >= 1
        empty = call("analytics scope", "GET", "/api/v1/analytics", headers=oh)
        assert empty["total_checks"] == 0
        history = call("real version history", "GET", "/api/v1/history", headers=ch)
        assert sum(v["check_id"] == cid for v in history["items"]) == 2
        notifications = call(
            "decision notification persisted",
            "GET",
            "/api/v1/notifications",
            headers=ch,
        )
        assert notifications["unread"] >= 1
        call(
            "notification read state",
            "PATCH",
            "/api/v1/notifications/read-all",
            headers=ch,
        )
        refreshed = call(
            "refresh rotation",
            "POST",
            "/api/v1/auth/refresh",
            json={"refresh_token": creator["refresh_token"]},
        )
        call(
            "old access revoked after refresh",
            "GET",
            "/api/v1/auth/me",
            401,
            headers=ch,
        )
        nh = {"Authorization": "Bearer " + refreshed["access_token"]}
        call("server logout", "POST", "/api/v1/auth/logout", headers=nh)
        call("logout revocation persists", "GET", "/api/v1/auth/me", 401, headers=nh)
        call(
            "revoked refresh rejected",
            "POST",
            "/api/v1/auth/refresh",
            401,
            json={"refresh_token": refreshed["refresh_token"]},
        )
        call(
            "reviewer removes temporary rule",
            "DELETE",
            f"/api/v1/library/rules/{rule['id']}?brand_name={brand}",
            headers=rh,
        )
        call(
            "draft deletion",
            "DELETE",
            f"/api/v1/drafts/{draft['id']}",
            headers=ch
            | {
                "Authorization": "Bearer "
                + call(
                    "fresh creator session",
                    "POST",
                    "/api/v1/auth/login",
                    json={"email": "creator@brandguard.demo", "password": "Demo@12345"},
                )["access_token"]
            },
        )
    print(
        f"\n{len(checks)} actual HTTP checks passed. No cloud/AI-provider success is implied."
    )


if __name__ == "__main__":
    main()
