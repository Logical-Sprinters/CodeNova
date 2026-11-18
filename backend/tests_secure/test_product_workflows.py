import io

from pypdf import PdfWriter
import pytest

from app import config
from app.main import app
from app.checks.llm.verifier import retrieve_facts
from fastapi.testclient import TestClient


def other_user(client):
    response = client.post(
        "/api/v1/auth/signup",
        json={
            "name": "Other Creator",
            "email": "other@example.com",
            "password": "OtherPass123!",
        },
    )
    assert response.status_code == 200
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def scan(client, headers, content="TODO free forever"):
    response = client.post(
        "/api/v1/brand/check",
        headers=headers,
        json={"brand_name": "Acme", "content": content},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_bearer_workflow_review_recheck_receipts_and_scopes(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    second = other_user(client)
    first = scan(client, creator)
    cid = first["check_id"]
    assert first["total_findings"] >= 2
    assert first["ai_verification"]["status"] == "abstained"
    assert client.get("/api/v1/analytics", headers=creator).json()["pending"] == 1
    assert client.get("/api/v1/analytics", headers=second).json()["total_checks"] == 0
    assert (
        client.get(
            "/api/v1/receipts/" + first["receipt_id"], headers=second
        ).status_code
        == 403
    )
    assert (
        client.post(
            "/api/v1/brand/" + cid + "/versions",
            headers=second,
            json={"content": "Edited"},
        ).status_code
        == 403
    )
    assert (
        client.patch(
            "/api/v1/reviews/" + cid + "/decision",
            headers=creator,
            json={"decision": "approved"},
        ).status_code
        == 403
    )
    approved = client.patch(
        "/api/v1/reviews/" + cid + "/decision",
        headers=reviewer,
        json={"decision": "approved", "expected_version": 1},
    )
    assert approved.status_code == 200, approved.text
    assert client.get("/api/v1/notifications", headers=creator).json()["unread"] == 1
    update = client.post(
        "/api/v1/brand/" + cid + "/versions",
        headers=creator,
        json={"content": "Final content", "expected_version": 1},
    )
    assert update.status_code == 200, update.text
    assert update.json()["content_version"] == 2
    assert update.json()["total_findings"] == 0
    assert (
        client.get("/api/v1/receipts/" + first["receipt_id"], headers=creator).json()[
            "approval_valid"
        ]
        is False
    )
    assert (
        client.post(
            "/api/v1/brand/" + cid + "/versions",
            headers=creator,
            json={"content": "stale", "expected_version": 1},
        ).status_code
        == 409
    )
    assert client.get("/api/v1/history", headers=creator).json()["total"] == 2
    assert client.get("/api/v1/history", headers=second).json()["total"] == 0
    # Restart-style lifecycle: persistent SQL records/tokens remain readable.
    with TestClient(app) as reopened:
        assert (
            reopened.get("/api/v1/analytics", headers=creator).json()["total_checks"]
            == 1
        )


def test_library_crud_enforces_new_rules_and_invalidates_approval(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]
    first = scan(client, creator, "A guaranteed outcome")
    cid = first["check_id"]
    assert (
        client.patch(
            "/api/v1/reviews/" + cid + "/decision",
            headers=reviewer,
            json={"decision": "approved"},
        ).status_code
        == 200
    )
    body = {
        "title": "Avoid guarantees",
        "brand_name": "Acme",
        "pattern": "guaranteed",
        "description": "Do not guarantee outcomes",
        "severity": "warning",
    }
    assert (
        client.post("/api/v1/library/rules", headers=creator, json=body).status_code
        == 403
    )
    rule = client.post("/api/v1/library/rules", headers=reviewer, json=body)
    assert rule.status_code == 201, rule.text
    rid = rule.json()["id"]
    assert (
        client.get("/api/v1/receipts/" + first["receipt_id"], headers=creator).json()[
            "rules_current"
        ]
        is False
    )
    second = scan(client, creator, "A guaranteed outcome")
    assert rid in [f["rule_id"] for f in second["findings"]]
    disabled = client.put(
        "/api/v1/library/rules/" + rid, headers=reviewer, json=body | {"enabled": False}
    )
    assert disabled.status_code == 200
    assert rid not in [
        f["rule_id"] for f in scan(client, creator, "A guaranteed outcome")["findings"]
    ]
    assert (
        client.post(
            "/api/v1/library/rules", headers=reviewer, json=body | {"pattern": "["}
        ).status_code
        == 422
    )
    assert (
        client.delete("/api/v1/library/rules/" + rid, headers=reviewer).status_code
        == 200
    )
    assert (
        client.delete("/api/v1/library/rules/" + rid, headers=reviewer).status_code
        == 404
    )
    guideline = client.post(
        "/api/v1/library/guidelines",
        headers=reviewer,
        json={"title": "Tone", "description": "Be clear and specific."},
    )
    assert guideline.status_code == 201
    assert (
        client.get("/api/v1/library/guidelines", headers=creator).json()["total"] == 1
    )
    assert (
        client.put(
            "/api/v1/library/guidelines/" + guideline.json()["id"],
            headers=reviewer,
            json={"title": "Tone revised"},
        ).status_code
        == 200
    )
    assert (
        client.delete(
            "/api/v1/library/guidelines/" + guideline.json()["id"], headers=reviewer
        ).status_code
        == 200
    )


def test_facts_require_text_verified_flag_and_source_url_validation(client, headers):
    reviewer = headers["reviewer"]
    assert (
        client.post(
            "/api/v1/library/facts",
            headers=reviewer,
            json={"title": "Source", "source_url": "https://example.com"},
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/library/facts",
            headers=reviewer,
            json={
                "title": "Source",
                "content": "Source text",
                "source_url": "javascript:alert(1)",
            },
        ).status_code
        == 422
    )
    body = {
        "title": "Acme pricing",
        "content": "Acme costs 49 dollars per month.",
        "verified": False,
    }
    response = client.post("/api/v1/library/facts", headers=reviewer, json=body)
    assert response.status_code == 201
    assert retrieve_facts("Acme costs 49 dollars") == []
    fid = response.json()["id"]
    assert (
        client.put(
            "/api/v1/library/facts/" + fid,
            headers=reviewer,
            json=body | {"verified": True},
        ).status_code
        == 200
    )
    assert retrieve_facts("Acme costs 49 dollars")[0]["id"] == fid


def test_drafts_are_private_durable_and_revision_checked(client, headers):
    creator = headers["creator"]
    other = other_user(client)
    body = {"title": "Campaign", "brand_name": "Acme", "content": "  Exact draft\n"}
    draft = client.post("/api/v1/drafts", headers=creator, json=body)
    assert draft.status_code == 201
    did = draft.json()["id"]
    assert client.get("/api/v1/drafts", headers=other).json()["total"] == 0
    assert (
        client.put("/api/v1/drafts/" + did, headers=other, json=body).status_code == 404
    )
    assert (
        client.put(
            "/api/v1/drafts/" + did,
            headers=creator,
            json=body | {"expected_revision": 1},
        ).json()["revision"]
        == 2
    )
    assert (
        client.put(
            "/api/v1/drafts/" + did,
            headers=creator,
            json=body | {"expected_revision": 1},
        ).status_code
        == 409
    )
    assert (
        client.get("/api/v1/drafts", headers=creator).json()["items"][0]["content"]
        == body["content"]
    )
    assert (
        client.post(
            "/api/v1/drafts", headers=creator, json=body | {"brand_name": "   "}
        ).status_code
        == 422
    )
    assert client.delete("/api/v1/drafts/" + did, headers=other).status_code == 404
    assert client.delete("/api/v1/drafts/" + did, headers=creator).status_code == 200


def test_private_document_upload_preview_download_and_draft_attachments(
    client, headers
):
    creator = headers["creator"]
    other = other_user(client)
    raw = "Acme source — actual document text.".encode()
    response = client.post(
        "/api/v1/files",
        headers=creator,
        files={"file": ("../../source.txt", raw, "text/plain")},
    )
    assert response.status_code == 201, response.text
    asset = response.json()
    assert asset["name"] == "source.txt"
    assert asset["extracted_text"] == raw.decode()
    assert (
        client.get(
            "/api/v1/files/" + asset["id"] + "/download", headers=creator
        ).content
        == raw
    )
    assert (
        client.get("/api/v1/files/" + asset["id"], headers=creator).json()[
            "extracted_text"
        ]
        == raw.decode()
    )
    assert (
        client.get(
            "/api/v1/files/" + asset["id"] + "/download", headers=other
        ).status_code
        == 403
    )
    assert (
        client.get(
            "/api/v1/files/" + asset["id"] + "/download", headers=headers["reviewer"]
        ).status_code
        == 200
    )
    body = {
        "title": "Attachment draft",
        "content": "Source",
        "attachments": [{"id": asset["id"], "name": "Spoofed name"}],
    }
    draft = client.post("/api/v1/drafts", headers=creator, json=body)
    assert draft.status_code == 201, draft.text
    assert draft.json()["attachments"][0]["name"] == "source.txt"
    assert client.post("/api/v1/drafts", headers=other, json=body).status_code == 403
    assert (
        client.post(
            "/api/v1/files?as_fact=true",
            headers=creator,
            files={"file": ("f.txt", raw)},
        ).status_code
        == 403
    )
    ingested = client.post(
        "/api/v1/files?as_fact=true",
        headers=headers["reviewer"],
        files={"file": ("f.txt", raw)},
    )
    assert ingested.status_code == 201
    assert ingested.json()["fact"]["verified"] is False


@pytest.mark.parametrize(
    "name,raw,status",
    [
        ("x.exe", b"abc", 415),
        ("x.pdf", b"not pdf", 415),
        ("x.txt", b"\xff", 422),
        ("x.txt", b"  ", 422),
        ("x.txt", b"", 413),
    ],
)
def test_invalid_documents_are_not_claimed_processed(
    client, headers, name, raw, status
):
    assert (
        client.post(
            "/api/v1/files", headers=headers["creator"], files={"file": (name, raw)}
        ).status_code
        == status
    )


def test_large_and_scanned_pdf_have_explicit_limits(client, headers):
    writer = PdfWriter()
    writer.add_blank_page(width=100, height=100)
    stream = io.BytesIO()
    writer.write(stream)
    result = client.post(
        "/api/v1/files",
        headers=headers["creator"],
        files={"file": ("scan.pdf", stream.getvalue(), "application/pdf")},
    )
    assert result.status_code == 422
    assert "OCR" in result.text
    assert (
        client.post(
            "/api/v1/files",
            headers=headers["creator"],
            files={"file": ("large.txt", b"a" * (5 * 1024 * 1024 + 1))},
        ).status_code
        == 413
    )


def test_notifications_are_scoped_and_mutations_persist(client, headers):
    scan(client, headers["creator"])
    assert (
        client.get("/api/v1/notifications", headers=headers["creator"]).json()["total"]
        == 0
    )
    items = client.get("/api/v1/notifications", headers=headers["reviewer"]).json()
    assert items["unread"] == 1
    nid = items["items"][0]["id"]
    assert (
        client.patch(
            "/api/v1/notifications/" + nid,
            headers=headers["creator"],
            json={"read": True},
        ).status_code
        == 404
    )
    assert (
        client.patch(
            "/api/v1/notifications/" + nid,
            headers=headers["reviewer"],
            json={"read": True},
        ).status_code
        == 200
    )
    assert (
        client.get("/api/v1/notifications", headers=headers["reviewer"]).json()[
            "unread"
        ]
        == 0
    )
    assert (
        client.patch(
            "/api/v1/notifications/read-all", headers=headers["reviewer"]
        ).status_code
        == 200
    )
    assert (
        client.delete(
            "/api/v1/notifications/" + nid, headers=headers["reviewer"]
        ).status_code
        == 200
    )
    assert (
        client.delete("/api/v1/notifications", headers=headers["reviewer"]).status_code
        == 200
    )
