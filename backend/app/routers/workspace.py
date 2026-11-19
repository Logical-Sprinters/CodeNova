from datetime import datetime, timezone
from uuid import uuid4
from collections import Counter

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app import config
from app.auth import can_read, get_user
from app.approval.store import load_records
from app.checks.llm.verifier import run_ai_verification
from app.storage import STORE_LOCK, read_json, write_json

router = APIRouter(prefix="/api/v1", tags=["Drafts, analytics and notifications"])


class Attachment(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str = Field(min_length=1, max_length=128)
    name: str = Field(default="", max_length=160)


class Draft(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(default="Untitled draft", min_length=1, max_length=160)
    brand_name: str = Field(default="Acme", min_length=1, max_length=128)
    content: str = Field(default="", max_length=200000)
    attachments: list[Attachment] = Field(default_factory=list, max_length=20)
    expected_revision: int | None = Field(default=None, ge=1)

    @field_validator("title", "brand_name")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("Value must not be blank")
        return value.strip()


class ReadNotification(BaseModel):
    read: bool = True


def path(name):
    return config.DATA_DIR / f"{name}.json"


def draft_data(body, user):
    assets = {asset["id"]: asset for asset in read_json(path("assets"), [])}
    references = []
    for reference in body.attachments:
        asset = assets.get(reference.id)
        if not asset or asset["creator_id"] != user["user_id"]:
            raise HTTPException(
                403, "A draft can reference only your own uploaded documents"
            )
        if not any(r["id"] == reference.id for r in references):
            references.append({"id": asset["id"], "name": asset["name"]})
    return body.model_dump(exclude={"expected_revision", "attachments"}) | {
        "attachments": references
    }


@router.get("/drafts")
def drafts(user=Depends(get_user)):
    items = [
        r for r in read_json(path("drafts"), []) if r["creator_id"] == user["user_id"]
    ]
    return {"items": list(reversed(items)), "total": len(items)}


@router.post("/drafts", status_code=201)
def create_draft(body: Draft, user=Depends(get_user)):
    with STORE_LOCK:
        item = draft_data(body, user) | {
            "id": str(uuid4()),
            "creator_id": user["user_id"],
            "revision": 1,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        items = read_json(path("drafts"), [])
        items.append(item)
        write_json(path("drafts"), items)
        return item


@router.put("/drafts/{draft_id}")
def save_draft(draft_id: str, body: Draft, user=Depends(get_user)):
    with STORE_LOCK:
        items = read_json(path("drafts"), [])
        original = next(
            (
                r
                for r in items
                if r["id"] == draft_id and r["creator_id"] == user["user_id"]
            ),
            None,
        )
        if original is None:
            raise HTTPException(404, "Draft not found")
        if (
            body.expected_revision is not None
            and original["revision"] != body.expected_revision
        ):
            raise HTTPException(409, "Draft changed. Reopen it before saving.")
        result = (
            original
            | draft_data(body, user)
            | {
                "revision": original["revision"] + 1,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        write_json(
            path("drafts"), [result if r["id"] == draft_id else r for r in items]
        )
        return result


@router.delete("/drafts/{draft_id}")
def delete_draft(draft_id: str, user=Depends(get_user)):
    with STORE_LOCK:
        items = read_json(path("drafts"), [])
        if not any(
            r["id"] == draft_id and r["creator_id"] == user["user_id"] for r in items
        ):
            raise HTTPException(404, "Draft not found")
        write_json(path("drafts"), [r for r in items if r["id"] != draft_id])
        return {"message": "Deleted"}


@router.get("/analytics")
def analytics(user=Depends(get_user)):
    records = [
        r
        for r in load_records()
        if can_read(r, user) and r.get("status") != "draft"
    ]
    counts = Counter(r["status"] for r in records)
    return {
        "total_checks": len(records),
        "pending": counts["pending"],
        "approved": counts["approved"],
        "rejected": counts["rejected"],
        "changes_requested": counts["changes_requested"],
        "paused_conflict": counts["paused_conflict"],
        "total_findings": sum(len(r["findings"]) for r in records),
        "scan_passed": sum(r.get("scan_status") == "passed" for r in records),
        "rule_counts": dict(
            Counter(f["rule_id"] for r in records for f in r["findings"])
        ),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/history")
def history(user=Depends(get_user)):
    versions = []
    for r in load_records():
        if can_read(r, user):
            versions.extend(
                v
                | {
                    "check_id": r["check_id"],
                    "brand_name": r["brand_name"],
                    "is_current_version": v["version"] == r["content_version"],
                }
                for v in r.get("versions", [])
            )
    return {"items": list(reversed(versions)), "total": len(versions)}


@router.get("/notifications")
def notifications(user=Depends(get_user)):
    raw = [
        r
        for r in read_json(path("notifications"), [])
        if r["user_id"] == user["user_id"]
    ]
    # Deduplicate historical 'review' notifications sharing the same check_id so
    # reviewers never see both v1 and v2 notifications for a single Review Queue record.
    seen_review_checks: set[str] = set()
    items = []
    for row in reversed(raw):
        cid = row.get("check_id")
        if row.get("type") == "review" and cid:
            if cid in seen_review_checks:
                continue
            seen_review_checks.add(cid)
        items.append(row)
    return {
        "items": items,
        "total": len(items),
        "unread": sum(not r["read"] for r in items),
    }


@router.patch("/notifications/read-all")
def mark_all(user=Depends(get_user)):
    with STORE_LOCK:
        items = read_json(path("notifications"), [])
        for item in items:
            if item["user_id"] == user["user_id"]:
                item["read"] = True
        write_json(path("notifications"), items)
    return {"message": "All notifications marked read"}


@router.delete("/notifications")
def clear_notifications(user=Depends(get_user)):
    with STORE_LOCK:
        items = read_json(path("notifications"), [])
        write_json(
            path("notifications"), [r for r in items if r["user_id"] != user["user_id"]]
        )
    return {"message": "Cleared"}


@router.patch("/notifications/{item_id}")
def mark_one(item_id: str, body: ReadNotification, user=Depends(get_user)):
    with STORE_LOCK:
        items = read_json(path("notifications"), [])
        item = next(
            (
                r
                for r in items
                if r["id"] == item_id and r["user_id"] == user["user_id"]
            ),
            None,
        )
        if item is None:
            raise HTTPException(404, "Notification not found")
        item["read"] = body.read
        write_json(path("notifications"), items)
        return item


@router.delete("/notifications/{item_id}")
def delete_notification(item_id: str, user=Depends(get_user)):
    with STORE_LOCK:
        items = read_json(path("notifications"), [])
        if not any(
            r["id"] == item_id and r["user_id"] == user["user_id"] for r in items
        ):
            raise HTTPException(404, "Notification not found")
        write_json(path("notifications"), [r for r in items if r["id"] != item_id])
    return {"message": "Deleted"}


@router.get("/system/status")
def status(user=Depends(get_user)):
    return {
        "auth_provider": config.AUTH_PROVIDER,
        "database": (
            "postgresql" if config.database_url().startswith("postgresql") else "sqlite"
        ),
        "ai_configured": config.AI_PROVIDER in {"openai", "openrouter", "gemini"}
        and bool(config.AI_API_KEY),
        "ai_provider": config.AI_PROVIDER,
        "ai_model": config.AI_MODEL if config.AI_API_KEY else None,
        "ai_access_live_verified": False,  # Configuration is not proof of wallet/provider access.
        "auth_email_configured": bool(
            config.SUPABASE_EMAIL_HOOK_SECRET and config.RESEND_API_KEY
        ),
        "storage": "supabase" if config.AUTH_PROVIDER == "supabase" else "local",
        "ai_verification_limit": 12000,
        "document_extraction_limit": 100000,
    }


@router.post("/system/ai-test")
def test_ai_connection(user: dict = Depends(get_user)):
    if user.get("role") not in {"reviewer", "admin"}:
        raise HTTPException(403, "Only reviewers can test live AI verification")
    configured = (
        config.AI_PROVIDER in {"openai", "openrouter", "gemini"}
        and bool(config.AI_API_KEY)
    )
    if not configured:
        return {
            "configured": False,
            "provider": config.AI_PROVIDER,
            "model": None,
            "live_ok": False,
            "status": "abstained",
            "message": "No AI key is configured in backend/.env. Run ENABLE_AI.bat or `python backend/manage.py configure-ai`, then restart the backend.",
            "citations": [],
        }

    probe_fact = {
        "id": "ai-probe-fact",
        "brand_name": "Acme",
        "title": "Acme SLA Reference",
        "content": "Acme Enterprise includes a 99.95% uptime SLA and costs $49 per month.",
        "verified": True,
        "enabled": True,
        "source_url": "https://example.com/sla",
        "version": "1.0.0",
        "channels": ["all"],
    }
    res = run_ai_verification(
        "Acme Enterprise includes a 99.95% uptime SLA and costs $49 per month.",
        brand_facts=[probe_fact],
        brand_name="Acme",
    )
    live_ok = res.get("status") in {"supported", "needs_review"}
    return {
        "configured": True,
        "provider": config.AI_PROVIDER,
        "model": res.get("model") or config.AI_MODEL,
        "live_ok": live_ok,
        "status": res.get("status", "abstained"),
        "message": res.get("message", ""),
        "citations": res.get("citations", []),
    }
