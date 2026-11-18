import copy
import hashlib
from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, UploadFile

from app.approval.store import (
    decide_record,
    generate_content_hash,
    get_record,
    list_records,
    verify_approval,
)
from app.audit.store import log_audit
from app.auth import can_read, get_user, require_read_access
from app.checks.grounding import filter_grounded_findings
from app.checks.llm.verifier import active_facts_for_brand
from app.notifications import notify
from app.receipts.store import record_decision
from app.routers.brand import resolve_assets
from app.rules_store.store import (
    get_brand_rule_versions,
    load_rule_store,
    resolve_active_rules,
)
from app.schemas.brand import ApprovalVerifyRequest, ReviewDecisionRequest
from app.storage import STORE_LOCK

router = APIRouter(tags=["Reviews and Approvals"])


def reverify_record_findings(record: dict) -> dict:
    """Server-side grounding check executed before any reviewer reads findings."""
    out = copy.deepcopy(record)
    brand_name = out.get("brand_name", "Acme")
    check_at = out.get("check_at") or out.get("created_at")
    channel = out.get("channel", "all")
    rules_version = out.get("rules_version")

    store = load_rule_store()
    brand = store["brands"].get(brand_name.strip().lower())
    version_override = None
    if brand and rules_version and rules_version in brand.get("versions", {}):
        version_override = rules_version

    active_rules, _ = resolve_active_rules(
        brand_name,
        check_at=check_at,
        channel=channel,
        version_override=version_override,
    )
    active_facts = active_facts_for_brand(
        brand_name=brand_name, check_at=check_at, channel=channel
    )
    grounded, dropped = filter_grounded_findings(
        out.get("findings", []),
        active_rules,
        out.get("content", ""),
        active_facts=active_facts,
        ocr_text=out.get("ocr_text", ""),
    )
    out["findings"] = grounded
    out["dropped_ungrounded_count"] = out.get("dropped_ungrounded_count", 0) + len(dropped)
    if dropped:
        out["grounding_reverified"] = True
        if out.get("scan_status") != "abstained_conflict":
            out["scan_status"] = "findings_detected" if grounded else "passed"
    return out


@router.get("/api/v1/reviews")
async def get_reviews(status: str | None = None, user: dict = Depends(get_user)):
    if status is not None and status not in {
        "pending",
        "approved",
        "rejected",
        "paused_conflict",
    }:
        raise HTTPException(
            422, "Status must be pending, approved, rejected or paused_conflict"
        )
    records = [
        reverify_record_findings(record)
        for record in list_records(status)
        if can_read(record, user)
    ]
    return {"reviews": records, "total": len(records)}


@router.patch("/api/v1/reviews/{check_id}/decision")
async def review_decision(
    check_id: str, request: ReviewDecisionRequest, user: dict = Depends(get_user)
):
    with STORE_LOCK:
        if user.get("role") not in {"reviewer", "admin"}:
            raise HTTPException(403, "Only reviewers can approve/reject")
        record = get_record(check_id)
        if record is None:
            raise HTTPException(404, "Check not found")
        if record.get("creator_id") == user["user_id"]:
            raise HTTPException(409, "Creators cannot approve their own submission")
        if request.decision not in {"approved", "rejected"}:
            raise HTTPException(400, "Decision must be approved or rejected.")
        if record.get("status") == "paused_conflict":
            raise HTTPException(
                409,
                "REVIEW PAUSED — Resolve the internal rule conflict before deciding this check.",
            )
        if (
            request.expected_version is not None
            and request.expected_version != record["content_version"]
        ):
            raise HTTPException(
                409, "Content changed while reviewing. Refresh the queue."
            )
        if record["status"] != "pending":
            raise HTTPException(409, "This version already has a decision.")
        rules = get_brand_rule_versions(record["brand_name"])
        current_rules = rules["current_version"] if rules else None
        if current_rules != record.get("rules_version"):
            raise HTTPException(
                409, "Brand rules changed. The owner must resubmit for fresh checks."
            )
        if generate_content_hash(record["content"]) != record["content_hash"]:
            raise HTTPException(
                409, "Stored content does not match its hash. Resubmit this check."
            )
        result = decide_record(
            check_id, request.decision, user["user_id"], request.note.strip()
        )
        record_decision(
            check_id,
            result["content_version"],
            request.decision,
            user["user_id"],
            request.note.strip(),
        )
        log_audit(
            "review_decision",
            user["user_id"],
            check_id,
            {
                "decision": request.decision,
                "content_version": result["content_version"],
                "content_hash": result["content_hash"],
                "composite_hash": result.get("composite_hash"),
                "seal_id": result.get("seal_id"),
                "rules_version": result["rules_version"],
                "receipt_id": result["receipt_id"],
            },
        )
        notify(
            [result["creator_id"]],
            "Review decision",
            f"{result['brand_name']} content v{result['content_version']} was {request.decision}.",
            "decision",
            check_id,
        )
        return {
            "message": f"Content {request.decision}.",
            "review": reverify_record_findings(result),
        }


def _run_verify_with_audit(
    *,
    check_id: str,
    brand_name: str,
    content: str,
    verify_at: str | None,
    asset_hashes: list[str] | None,
    user: dict,
):
    record = get_record(check_id)
    if record is not None:
        require_read_access(record, user)
    rules = get_brand_rule_versions(brand_name)
    current_version = rules["current_version"] if rules else None
    result = verify_approval(
        check_id,
        brand_name,
        content,
        current_version,
        verify_at=verify_at,
        asset_hashes=asset_hashes,
    )
    log_audit(
        "verify_approval",
        user["user_id"],
        check_id,
        {
            "valid": result["valid"],
            "seal_status": result.get("seal_status"),
            "tamper_detected": result.get("seal_status") == "VOIDED_TAMPERED",
            "seal_id": result.get("seal_id"),
            "reason": result["reason"],
            "rule_changes": result.get("rule_changes", []),
            "tampered_tokens": result.get("tampered_tokens", []),
            "submitted_hash": generate_content_hash(content),
            "content_version": record.get("content_version") if record else None,
        },
    )
    return result


@router.post("/api/v1/approvals/verify")
async def check_approval(
    request: ApprovalVerifyRequest,
    user: dict = Depends(get_user),
    authorization: str = Header(default=""),
):
    with STORE_LOCK:
        asset_hashes = None
        if request.asset_ids:
            resolved = resolve_assets(request.asset_ids, user, authorization)
            asset_hashes = [a["sha256"] for a in resolved]
        return _run_verify_with_audit(
            check_id=request.check_id,
            brand_name=request.brand_name,
            content=request.content,
            verify_at=request.verify_at,
            asset_hashes=asset_hashes,
            user=user,
        )


@router.post("/api/v1/approvals/verify-upload")
async def verify_approval_upload(
    check_id: str = Form(...),
    brand_name: str = Form(...),
    content: str | None = Form(default=None),
    verify_at: str | None = Form(default=None),
    file: UploadFile | None = File(default=None),
    user: dict = Depends(get_user),
):
    """Verify an approval seal against pasted text or a re-uploaded text/binary asset."""
    with STORE_LOCK:
        submitted_text = content
        asset_hashes: list[str] | None = None
        if file is not None:
            raw = await file.read(5 * 1024 * 1024 + 1)
            if not raw or len(raw) > 5 * 1024 * 1024:
                raise HTTPException(413, "Upload a nonempty file no larger than 5 MB")
            try:
                decoded = raw.decode("utf-8")
                if submitted_text is None:
                    submitted_text = decoded
                else:
                    asset_hashes = [hashlib.sha256(raw).hexdigest()]
            except UnicodeDecodeError:
                asset_hashes = [hashlib.sha256(raw).hexdigest()]
                if submitted_text is None:
                    record = get_record(check_id.strip())
                    submitted_text = record["content"] if record else ""

        if submitted_text is None or not submitted_text.strip():
            raise HTTPException(422, "Provide content text or a readable UTF-8 file to verify.")

        return _run_verify_with_audit(
            check_id=check_id.strip(),
            brand_name=brand_name.strip(),
            content=submitted_text,
            verify_at=verify_at,
            asset_hashes=asset_hashes,
            user=user,
        )
