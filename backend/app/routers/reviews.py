import copy
from datetime import datetime, timedelta, timezone
import hashlib
from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, UploadFile

from app import config
from app.approval.store import (
    amend_record_decision,
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
from app.notifications import mark_review_notifications_read, notify
from app.receipts.store import record_decision
from app.routers.brand import resolve_assets
from app.rules_store.store import (
    get_brand_rule_versions,
    load_rule_store,
    resolve_active_rules,
)
from app.schemas.brand import (
    ApprovalVerifyRequest,
    ReviewAmendRequest,
    ReviewDecisionRequest,
)
from app.storage import STORE_LOCK, read_json

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


def _attach_amend_metadata(record: dict) -> dict:
    window_minutes = config.DECISION_AMEND_WINDOW_MINUTES
    record["amend_window_minutes"] = window_minutes
    record["can_amend"] = False
    record["amend_deadline"] = None
    record["amend_remaining_seconds"] = 0
    if record.get("status") not in {"approved", "rejected", "changes_requested"}:
        return record
    anchor_raw = record.get("initial_decided_at") or record.get("decided_at")
    if not anchor_raw:
        return record
    try:
        normalized = (
            anchor_raw[:-1] + "+00:00"
            if str(anchor_raw).endswith(("Z", "z"))
            else str(anchor_raw)
        )
        anchor_dt = datetime.fromisoformat(normalized)
        if anchor_dt.tzinfo is None:
            anchor_dt = anchor_dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return record
    deadline = anchor_dt.astimezone(timezone.utc) + timedelta(minutes=window_minutes)
    now_dt = datetime.now(timezone.utc)
    remaining = max(0, int((deadline - now_dt).total_seconds()))
    record["amend_deadline"] = deadline.isoformat()
    record["can_amend"] = now_dt <= deadline
    record["amend_remaining_seconds"] = remaining
    return record


@router.get("/api/v1/reviews")
async def get_reviews(status: str | None = None, user: dict = Depends(get_user)):
    if status is not None and status not in {
        "pending",
        "approved",
        "rejected",
        "changes_requested",
        "paused_conflict",
    }:
        raise HTTPException(
            422,
            "Status must be pending, approved, rejected, changes_requested or paused_conflict",
        )
    users_by_id = {
        u.get("user_id"): u
        for u in read_json(config.DATA_DIR / "users.json", [])
        if u.get("user_id")
    }
    records = []
    for record in list_records(status):
        if record.get("status") == "draft":
            continue
        if not can_read(record, user):
            continue
        enriched = _attach_amend_metadata(reverify_record_findings(record))
        creator = users_by_id.get(enriched.get("creator_id"), {})
        if not enriched.get("creator_name"):
            enriched["creator_name"] = (
                creator.get("name")
                or creator.get("email")
                or enriched.get("creator_id")
                or "Unknown"
            )
        if not enriched.get("creator_email"):
            enriched["creator_email"] = creator.get("email") or ""
        rev_id = enriched.get("reviewer")
        if rev_id:
            rev_user = users_by_id.get(rev_id, {})
            if not enriched.get("reviewer_name"):
                enriched["reviewer_name"] = (
                    rev_user.get("name") or rev_user.get("email") or rev_id
                )
            if not enriched.get("reviewer_email"):
                enriched["reviewer_email"] = rev_user.get("email") or ""
        records.append(enriched)
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
        if request.decision not in {"approved", "rejected", "changes_requested"}:
            raise HTTPException(
                400, "Decision must be approved, rejected, or changes_requested."
            )
        if request.decision == "changes_requested" and not request.note.strip():
            raise HTTPException(400, "Explain what needs to change before submitting.")
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
            check_id,
            request.decision,
            user["user_id"],
            request.note.strip(),
            reviewer_name=user.get("name"),
            reviewer_email=user.get("email"),
        )
        record_decision(
            check_id,
            result["content_version"],
            request.decision,
            user["user_id"],
            request.note.strip(),
            seal_id=result.get("seal_id"),
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
        if request.decision == "changes_requested":
            notif_title = "Changes requested"
            notif_body = f"{result['brand_name']} needs changes: {request.note.strip()[:140]}"
        else:
            notif_title = "Review decision"
            ver_note = (
                f" (rev {result['content_version']})"
                if (result.get("content_version") or 1) > 1
                else ""
            )
            notif_body = (
                f"{result['brand_name']} submission{ver_note} was {request.decision}."
            )
        notify(
            [result["creator_id"]],
            notif_title,
            notif_body,
            "decision",
            check_id,
        )
        mark_review_notifications_read(check_id)
        return {
            "message": f"Content {request.decision}.",
            "review": _attach_amend_metadata(reverify_record_findings(result)),
        }


@router.post("/api/v1/reviews/{check_id}/amend")
async def amend_review_decision(
    check_id: str, request: ReviewAmendRequest, user: dict = Depends(get_user)
):
    with STORE_LOCK:
        if user.get("role") not in {"reviewer", "admin"}:
            raise HTTPException(403, "Only reviewers can amend decisions")
        record = get_record(check_id)
        if record is None:
            raise HTTPException(404, "Check not found")
        if record.get("creator_id") == user["user_id"]:
            raise HTTPException(
                409, "Creators cannot amend decisions on their own submission"
            )
        if (
            request.expected_version is not None
            and request.expected_version != record["content_version"]
        ):
            raise HTTPException(
                409, "Content changed while reviewing. Refresh the queue."
            )
        old_status = record.get("status")
        if old_status not in {"approved", "rejected", "changes_requested"}:
            raise HTTPException(
                409, "Only decided submissions can have their decision amended."
            )
        if request.decision == old_status:
            raise HTTPException(
                400, "Select a different decision than the current status."
            )
        if request.decision == "approved":
            rules = get_brand_rule_versions(record["brand_name"])
            current_rules = rules["current_version"] if rules else None
            if current_rules != record.get("rules_version"):
                raise HTTPException(
                    409,
                    "Brand rules changed. The owner must resubmit for fresh checks.",
                )
            if generate_content_hash(record["content"]) != record["content_hash"]:
                raise HTTPException(
                    409,
                    "Stored content does not match its hash. Resubmit this check.",
                )

        outcome, err = amend_record_decision(
            check_id,
            request.decision,
            user["user_id"],
            request.reason,
            window_minutes=config.DECISION_AMEND_WINDOW_MINUTES,
            reviewer_name=user.get("name"),
            reviewer_email=user.get("email"),
        )
        if err == "window_expired":
            raise HTTPException(
                409,
                f"Decision amendment window expired ({config.DECISION_AMEND_WINDOW_MINUTES} min limit). Ask the owner to submit a new revision.",
            )
        if err == "invalid_status":
            raise HTTPException(
                409, "Only decided submissions can have their decision amended."
            )
        if err == "same_decision":
            raise HTTPException(
                400, "Select a different decision than the current status."
            )
        if err or not outcome:
            raise HTTPException(404, "Check not found")

        updated = outcome["record"]
        prev_decision = outcome["previous_decision"]
        revoked_seal_id = outcome.get("revoked_seal_id")

        record_decision(
            check_id,
            updated["content_version"],
            request.decision,
            user["user_id"],
            request.reason,
            seal_id=updated.get("seal_id"),
            is_amendment=True,
        )
        log_audit(
            "amend_decision",
            user["user_id"],
            check_id,
            {
                "previous_decision": prev_decision,
                "new_decision": request.decision,
                "reason": request.reason,
                "content_version": updated["content_version"],
                "content_hash": updated["content_hash"],
                "seal_id": updated.get("seal_id"),
                "revoked_seal_id": revoked_seal_id,
                "amend_window_minutes": config.DECISION_AMEND_WINDOW_MINUTES,
                "receipt_id": updated.get("receipt_id"),
            },
        )
        if prev_decision == "approved":
            notif_title = "Approval revoked — decision amended"
            notif_body = (
                f"{updated['brand_name']} approval was revoked and changed to "
                f"{request.decision.replace('_', ' ')}: {request.reason[:140]}"
            )
        else:
            notif_title = "Review decision amended"
            notif_body = (
                f"{updated['brand_name']} decision changed from "
                f"{prev_decision.replace('_', ' ')} to "
                f"{request.decision.replace('_', ' ')}: {request.reason[:140]}"
            )
        notify(
            [updated["creator_id"]],
            notif_title,
            notif_body,
            "decision",
            check_id,
        )
        mark_review_notifications_read(check_id)
        return {
            "message": f"Decision amended from {prev_decision} to {request.decision}.",
            "previous_decision": prev_decision,
            "revoked_seal_id": revoked_seal_id,
            "review": _attach_amend_metadata(reverify_record_findings(updated)),
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
