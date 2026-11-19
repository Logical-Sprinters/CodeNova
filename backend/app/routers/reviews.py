from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.checks.source_conflicts import detect_source_conflicts
from app.approval.store import (
    decide_record,
    generate_content_hash,
    get_record,
    list_records,
    load_records,
    save_records,
    snapshot,
    verify_approval,
)
from app.audit.store import log_audit
from app.auth import can_read, get_user, require_read_access
from app.receipts.store import record_decision
from app.rules_store.store import get_brand_rule_versions
from app.schemas.brand import ApprovalVerifyRequest, ReviewDecisionRequest
from app.storage import STORE_LOCK
from app.conflicts.store import detect_conflicts
from app.notifications import notify

router = APIRouter(tags=["Reviews and Approvals"])


@router.get("/api/v1/reviews")
async def get_reviews(status: str | None = None, user: dict = Depends(get_user)):
    if status is not None and status not in {"pending", "approved", "rejected"}:
        raise HTTPException(422, "Status must be pending, approved or rejected")
    records = [record for record in list_records(status) if can_read(record, user)]
    for record in records:
        # Re-evaluate against the latest trusted library sources for reviewer visibility.
        record["source_conflicts"] = detect_source_conflicts(
            record["brand_name"]
        ) + detect_conflicts(
            record["brand_name"], record["content"], persist=False
        )
    return {"reviews": records, "total": len(records)}


@router.patch("/api/v1/reviews/{check_id}/decision")
async def review_decision(
    check_id: str, request: ReviewDecisionRequest, user: dict = Depends(get_user)
):
    source_conflict_detected = False
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
        if (
            request.expected_version is not None
            and request.expected_version != record["content_version"]
        ):
            raise HTTPException(
                409, "Content changed while reviewing. Refresh the queue."
            )
        if record["status"] != "pending":
            raise HTTPException(409, "This version already has a decision.")
        current_conflicts = detect_source_conflicts(record["brand_name"])
        record["source_conflicts"] = current_conflicts
        if request.decision == "approved" and current_conflicts:
            raise HTTPException(
                status_code=409,
                detail={
                    "message": "Approval blocked: trusted brand sources conflict. "
                    "A reviewer must reconcile the source records before approval.",
                    "source_conflicts": current_conflicts,
                },
            )
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
        active_conflicts = [
            conflict
            for conflict in detect_conflicts(record["brand_name"], record["content"])
            if conflict.get("status") == "unresolved"
        ]
        if active_conflicts:
            from app.routers.brand import attach_receipt, inspect_content

            inspection = inspect_content(
                record["content"],
                record["brand_name"],
                source_conflicts=active_conflicts,
            )
            record.update(inspection, source_conflicts=active_conflicts)
            record["scan_status"] = "source_conflict"
            record["updated_at"] = datetime.now(timezone.utc).isoformat()
            attach_receipt(record)
            if record.get("versions"):
                record["versions"][-1] = snapshot(record)
            records = load_records()
            save_records(
                [record if item["check_id"] == check_id else item for item in records]
            )
            log_audit(
                "source_conflict_pause",
                user["user_id"],
                check_id,
                {
                    "conflict_ids": [item["id"] for item in active_conflicts],
                    "receipt_id": record["receipt_id"],
                    "decision_blocked": request.decision,
                },
            )
            source_conflict_detected = True
        else:
            result = decide_record(
                check_id, request.decision, user["user_id"], request.note.strip()
            )
            record_decision(
                check_id,
                result["content_version"],
                request.decision,
                user["user_id"],
                request.note.strip(),
                approval_fingerprint=result.get("approval_fingerprint"),
                approval_fingerprint_algorithm=result.get(
                    "approval_fingerprint_algorithm"
                ),
            )
            log_audit(
                "review_decision",
                user["user_id"],
                check_id,
                {
                    "decision": request.decision,
                    "content_version": result["content_version"],
                    "content_hash": result["content_hash"],
                    "rules_version": result["rules_version"],
                    "receipt_id": result["receipt_id"],
                    "approval_fingerprint": result.get("approval_fingerprint"),
                    "approval_fingerprint_algorithm": result.get(
                        "approval_fingerprint_algorithm"
                    ),
                },
            )
            notify(
                [result["creator_id"]],
                "Review decision",
                f"{result['brand_name']} content v{result['content_version']} was {request.decision}.",
                "decision",
                check_id,
            )
    if source_conflict_detected:
        raise HTTPException(
            409,
            "Review paused: a source conflict was detected. An authorized reviewer must resolve it before deciding.",
        )
    return {"message": f"Content {request.decision}.", "review": result}


@router.post("/api/v1/approvals/verify")
async def check_approval(
    request: ApprovalVerifyRequest, user: dict = Depends(get_user)
):
    with STORE_LOCK:
        record = get_record(request.check_id)
        if record is not None:
            require_read_access(record, user)
        rules = get_brand_rule_versions(request.brand_name)
        current_version = rules["current_version"] if rules else None
        result = verify_approval(
            request.check_id, request.brand_name, request.content, current_version
        )
        log_audit(
            "verify_approval",
            user["user_id"],
            request.check_id,
            {
                "valid": result["valid"],
                "reason": result["reason"],
                "submitted_hash": generate_content_hash(request.content),
                "content_version": record.get("content_version") if record else None,
            },
        )
        return result
