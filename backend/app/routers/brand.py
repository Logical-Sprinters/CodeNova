from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException

from app.approval.store import (
    create_record,
    generate_content_hash,
    get_record,
    load_records,
    save_records,
    snapshot,
)
from app.audit.store import log_audit
from app.auth import get_user
from app.checks.deterministic.engine import run_deterministic_checks
from app.checks.llm.verifier import run_ai_verification
from app.receipts.store import create_receipt
from app.rules_store.store import get_brand_rule_versions
from app.schemas.brand import (
    BrandCheckRequest,
    BrandCheckResponse,
    ContentVersionRequest,
)
from app.storage import STORE_LOCK
from app.notifications import notify_reviewers

router = APIRouter(prefix="/api/v1/brand", tags=["Brand Checks"])


def inspect_content(content, brand_name):
    deterministic = [
        finding.model_dump()
        for finding in run_deterministic_checks(content, brand_name)
    ]
    ai_result = run_ai_verification(content, brand_name=brand_name)
    findings = deterministic + ai_result.get("findings", [])
    rules = get_brand_rule_versions(brand_name)
    return {
        "content": content,
        "content_hash": generate_content_hash(content),
        "rules_version": rules["current_version"] if rules else None,
        "findings": findings,
        "deterministic_count": len(deterministic),
        "scan_status": "findings_detected" if findings else "passed",
        "ai_verification": ai_result,
    }


def attach_receipt(record):
    receipt = create_receipt(
        {
            "check_id": record["check_id"],
            "creator_id": record["creator_id"],
            "brand_name": record["brand_name"],
            "content_hash": record["content_hash"],
            "content_version": record["content_version"],
            "rules_version": record["rules_version"],
            "deterministic_engine": "1.0",
            "deterministic_findings": record.get(
                "deterministic_count", len(record["findings"])
            ),
            "scan_status": record["scan_status"],
            "ai_verification": record["ai_verification"],
            "final_status": record["status"],
        }
    )
    record["receipt_id"] = receipt["receipt_id"]


def response_for(record):
    # Scan success is NOT human approval. Even clean text can be reviewed.
    return BrandCheckResponse(
        check_id=record["check_id"],
        receipt_id=record["receipt_id"],
        brand_name=record["brand_name"],
        status="review_required",
        findings=record["findings"],
        total_findings=len(record["findings"]),
        content_version=record["content_version"],
        scan_status=record["scan_status"],
        review_status=record["status"],
        rules_version=record.get("rules_version"),
        ai_verification=record.get("ai_verification"),
    )


@router.post("/check", response_model=BrandCheckResponse)
async def check_brand(request: BrandCheckRequest, user: dict = Depends(get_user)):
    with STORE_LOCK:
        now = datetime.now(timezone.utc).isoformat()
        record = {
            "check_id": str(uuid4()),
            "brand_name": request.brand_name,
            "creator_id": user["user_id"],
            "content_version": 1,
            "created_at": now,
            "updated_at": now,
            "status": "pending",
            "reviewer": None,
            "review_note": None,
            "decided_at": None,
            **inspect_content(request.content, request.brand_name),
        }
        attach_receipt(record)
        record["versions"] = [snapshot(record)]
        create_record(record)
        log_audit(
            "create_check",
            user["user_id"],
            record["check_id"],
            {
                "brand": record["brand_name"],
                "content_version": 1,
                "content_hash": record["content_hash"],
                "rules_version": record["rules_version"],
                "scan_status": record["scan_status"],
                "receipt_id": record["receipt_id"],
            },
        )
        notify_reviewers(
            record["check_id"],
            f"{record['brand_name']} content v{record['content_version']} awaits review.",
        )
        return response_for(record)


@router.post("/{check_id}/versions", response_model=BrandCheckResponse)
async def submit_version(
    check_id: str, request: ContentVersionRequest, user: dict = Depends(get_user)
):
    with STORE_LOCK:
        record = get_record(check_id)
        if record is None:
            raise HTTPException(404, "Check not found")
        if record.get("creator_id") != user["user_id"]:
            raise HTTPException(403, "Only the submission owner can edit this check")
        current_version = record.get("content_version", 1)
        if (
            request.expected_version is not None
            and request.expected_version != current_version
        ):
            raise HTTPException(
                409, "Content was updated. Refresh before submitting another version."
            )
        old_hash = record["content_hash"]
        old_status = record["status"]
        # Re-run the real checker and fetch the CURRENT rules version on every edit.
        inspection = inspect_content(request.content, record["brand_name"])
        record.update(inspection)
        record.update(
            content_version=current_version + 1,
            status="pending",
            reviewer=None,
            review_note=None,
            decided_at=None,
            updated_at=datetime.now(timezone.utc).isoformat(),
        )
        attach_receipt(record)
        record.setdefault("versions", []).append(snapshot(record))
        records = load_records()
        records = [record if row["check_id"] == check_id else row for row in records]
        save_records(records)
        log_audit(
            "submit_version",
            user["user_id"],
            check_id,
            {
                "old_hash": old_hash,
                "new_hash": record["content_hash"],
                "content_version": record["content_version"],
                "rules_version": record["rules_version"],
                "scan_status": record["scan_status"],
                "receipt_id": record["receipt_id"],
                "previous_status": old_status,
                "approval_invalidated": old_status == "approved",
            },
        )
        notify_reviewers(
            record["check_id"],
            f"{record['brand_name']} content v{record['content_version']} awaits review.",
        )
        return response_for(record)


@router.get("/rules/{brand_name}")
async def get_rules(brand_name: str):
    result = get_brand_rule_versions(brand_name)
    if not result:
        raise HTTPException(404, "Brand rules not found")
    return result
