import json
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

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
from app.checks.deterministic.engine import BASE_RULES, run_deterministic_checks
from app.checks.llm.verifier import abstain, run_ai_verification
from app.checks.multimodal import analyze_image
from app.checks.source_conflicts import detect_source_conflicts
from app.receipts.store import create_receipt
from app.rules_store.store import get_brand_rule_versions, get_brand_rules
from app.schemas.brand import (
    BrandCheckRequest,
    BrandCheckResponse,
    ContentVersionRequest,
    PreflightRequest,
)
from app.storage import STORE_LOCK
from app.notifications import notify_reviewers
from app.conflicts.store import detect_conflicts

router = APIRouter(prefix="/api/v1/brand", tags=["Brand Checks"])
MAX_IMAGE_BYTES = 8 * 1024 * 1024
MAX_REFERENCE_BYTES = 2 * 1024 * 1024


def inspect_content(content, brand_name, source_conflicts=None):
    deterministic = [
        finding.model_dump()
        for finding in run_deterministic_checks(content, brand_name)
    ]
    all_source_conflicts = detect_source_conflicts(brand_name) + (
        source_conflicts or []
    )
    ai_result = (
        abstain(
            "Source-of-truth conflict detected. AI verification is paused until an authorized reviewer resolves it."
        )
        if all_source_conflicts
        else run_ai_verification(content, brand_name=brand_name)
    )
    findings = deterministic + ai_result.get("findings", [])
    rules = get_brand_rule_versions(brand_name)
    return {
        "content": content,
        "content_hash": generate_content_hash(content),
        "rules_version": rules["current_version"] if rules else None,
        "findings": findings,
        "deterministic_count": len(deterministic),
        "scan_status": (
            "source_conflict"
            if all_source_conflicts
            else "findings_detected"
            if findings
            else "passed"
        ),
        "ai_verification": ai_result,
        "source_conflicts": all_source_conflicts,
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
            "visual_analysis": record.get("visual_analysis"),
            "source_conflicts": record.get("source_conflicts", []),
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
        status=(
            "review_paused"
            if record.get("source_conflicts")
            else "review_required"
        ),
        findings=record["findings"],
        total_findings=len(record["findings"])
        + len((record.get("visual_analysis") or {}).get("violations", [])),
        content_version=record["content_version"],
        scan_status=record["scan_status"],
        review_status=record["status"],
        rules_version=record.get("rules_version"),
        ai_verification=record.get("ai_verification"),
        visual_analysis=record.get("visual_analysis"),
        checked_content=record["content"],
        source_conflicts=record.get("source_conflicts", []),
    )


def create_check(user, brand_name, content, visual_analysis=None):
    with STORE_LOCK:
        now = datetime.now(timezone.utc).isoformat()
        source_conflicts = detect_conflicts(brand_name, content)
        unresolved_conflicts = [
            conflict for conflict in source_conflicts
            if conflict["status"] == "unresolved"
        ]
        inspection = inspect_content(
            content, brand_name, source_conflicts=unresolved_conflicts
        )
        violations = (visual_analysis or {}).get("violations", [])
        record = {
            "check_id": str(uuid4()),
            "brand_name": brand_name,
            "creator_id": user["user_id"],
            "content_version": 1,
            "created_at": now,
            "updated_at": now,
            "status": "pending",
            "reviewer": None,
            "review_note": None,
            "decided_at": None,
            "visual_analysis": visual_analysis,
            "source_conflicts": unresolved_conflicts,
            **inspection,
        }
        if record.get("source_conflicts"):
            record["scan_status"] = "source_conflict"
            record["status"] = "pending"
        elif violations or record["findings"]:
            record["scan_status"] = "findings_detected"
        elif visual_analysis and visual_analysis.get("status") != "complete":
            record["scan_status"] = "partial"
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
                "visual_analysis": visual_analysis is not None,
            },
        )
        notify_reviewers(
            record["check_id"],
            f"{record['brand_name']} content v{record['content_version']} awaits review.",
        )
        return response_for(record)


def recheck_after_source_resolution(resolved_conflict_ids, actor_id):
    from app.approval.store import load_records, save_records
    from app.notifications import notify

    resolved_ids = set(resolved_conflict_ids)
    if not resolved_ids:
        return []
    rechecked = []
    with STORE_LOCK:
        records = load_records()
        for record in records:
            if record.get("status") != "pending":
                continue
            prior_conflicts = record.get("source_conflicts") or []
            if not any(item.get("id") in resolved_ids for item in prior_conflicts):
                continue

            active_conflicts = [
                conflict
                for conflict in detect_conflicts(record["brand_name"], record["content"])
                if conflict.get("status") == "unresolved"
            ]
            inspection = inspect_content(
                record["content"],
                record["brand_name"],
                source_conflicts=active_conflicts,
            )
            previous_scan_status = record.get("scan_status")
            visual_violations = (record.get("visual_analysis") or {}).get(
                "violations", []
            )
            if inspection["source_conflicts"]:
                scan_status = "source_conflict"
            elif inspection["findings"] or visual_violations:
                scan_status = "findings_detected"
            elif (
                record.get("visual_analysis")
                and record["visual_analysis"].get("status") != "complete"
            ):
                scan_status = "partial"
            else:
                scan_status = "passed"
            record.update(
                inspection,
                source_conflicts=inspection["source_conflicts"],
                scan_status=scan_status,
                updated_at=datetime.now(timezone.utc).isoformat(),
            )
            attach_receipt(record)
            if record.get("versions"):
                record["versions"][-1] = snapshot(record)
            rechecked.append(
                {
                    "check_id": record["check_id"],
                    "creator_id": record["creator_id"],
                    "scan_status": scan_status,
                    "previous_scan_status": previous_scan_status,
                    "receipt_id": record["receipt_id"],
                }
            )
            log_audit(
                "source_conflict_recheck",
                actor_id,
                record["check_id"],
                {
                    "resolved_conflict_ids": sorted(resolved_ids),
                    "previous_scan_status": previous_scan_status,
                    "scan_status": scan_status,
                    "receipt_id": record["receipt_id"],
                },
            )
        if rechecked:
            save_records(records)

    for item in rechecked:
        notify(
            [item["creator_id"]],
            "Source conflict resolved",
            (
                "Your submission has been rechecked and remains paused because another source conflict is unresolved."
                if item["scan_status"] == "source_conflict"
                else f"Your submission has been rechecked ({item['scan_status']}). It is pending authorized review."
            ),
            "review",
            item["check_id"],
        )
        if item["scan_status"] != "source_conflict":
            notify_reviewers(
                item["check_id"],
                f"Rechecked {item['check_id']} after source conflict resolution; it awaits review.",
            )
    return rechecked


@router.post("/check", response_model=BrandCheckResponse)
async def check_brand(request: BrandCheckRequest, user: dict = Depends(get_user)):
    return create_check(user, request.brand_name, request.content)


@router.post("/preflight")
async def preflight_check(
    request: PreflightRequest, user: dict = Depends(get_user)
):
    content = request.content
    rules = get_brand_rules(request.brand_name)
    rules_checked = sum(
        1 for rule in BASE_RULES + (rules["rules"] if rules else [])
        if rule.get("enabled", True)
    )
    findings = (
        [
            finding.model_dump()
            for finding in run_deterministic_checks(content, request.brand_name)
        ]
        if content.strip()
        else []
    )
    source_conflicts = (
        detect_source_conflicts(request.brand_name)
        + detect_conflicts(request.brand_name, content, persist=False)
        if content.strip()
        else []
    )
    unresolved_conflicts = [
        conflict for conflict in source_conflicts
        if conflict.get("status") == "unresolved"
    ]
    rule_versions = get_brand_rule_versions(request.brand_name)
    return {
        "status": (
            "source_conflict"
            if unresolved_conflicts
            else "checked"
            if content.strip()
            else "empty"
        ),
        "findings": findings,
        "source_conflicts": unresolved_conflicts,
        "rules_checked": rules_checked,
        "rules_version": (
            rule_versions["current_version"] if rule_versions else None
        ),
        "preliminary_only": True,
    }


async def read_image(file: UploadFile | None, limit: int, label: str):
    if file is None:
        return None
    raw = await file.read(limit + 1)
    if not raw:
        raise HTTPException(422, f"{label} image is empty")
    if len(raw) > limit:
        raise HTTPException(
            413, f"{label} image exceeds the {limit // (1024 * 1024)} MB limit"
        )
    return raw


@router.post("/multimodal-check", response_model=BrandCheckResponse)
async def multimodal_check(
    image: UploadFile = File(...),
    brand_name: str = Form(..., min_length=1, max_length=128),
    caption: str = Form(default="", max_length=200_000),
    approved_colors: str = Form(default="[]", max_length=512),
    approved_logo: UploadFile | None = File(default=None),
    deprecated_logo: UploadFile | None = File(default=None),
    user: dict = Depends(get_user),
):
    if not brand_name.strip():
        raise HTTPException(422, "Brand name must not be blank")
    try:
        colors = json.loads(approved_colors)
        if (
            not isinstance(colors, list)
            or len(colors) > 12
            or any(not isinstance(color, str) for color in colors)
        ):
            raise ValueError
    except (json.JSONDecodeError, ValueError):
        raise HTTPException(
            422, "Approved colors must be a JSON array of up to 12 HEX colors"
        )

    image_raw = await read_image(image, MAX_IMAGE_BYTES, "Marketing asset")
    approved_raw = await read_image(
        approved_logo, MAX_REFERENCE_BYTES, "Approved logo"
    )
    deprecated_raw = await read_image(
        deprecated_logo, MAX_REFERENCE_BYTES, "Deprecated logo"
    )
    try:
        visual_analysis = analyze_image(
            image_raw,
            colors,
            approved_logo=approved_raw,
            deprecated_logo=deprecated_raw,
        )
    except ValueError as error:
        raise HTTPException(422, str(error)) from error

    ocr = visual_analysis["ocr"]
    ocr_text = ocr["text"]
    if ocr["status"] != "complete" and not caption.strip():
        raise HTTPException(503, ocr["reason"])
    content = caption
    if ocr_text:
        content = f"{caption}\n\n{ocr_text}" if caption else ocr_text
    if len(content) > 200_000:
        raise HTTPException(
            422, "Combined caption and OCR text must not exceed 200,000 characters"
        )
    if not content.strip():
        raise HTTPException(422, "Add a caption or upload an image containing readable text")
    return create_check(user, brand_name.strip(), content, visual_analysis)


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
        source_conflicts = detect_conflicts(record["brand_name"], request.content)
        unresolved_conflicts = [
            conflict
            for conflict in source_conflicts
            if conflict["status"] == "unresolved"
        ]
        inspection = inspect_content(
            request.content,
            record["brand_name"],
            source_conflicts=unresolved_conflicts,
        )
        record.update(
            inspection, source_conflicts=inspection["source_conflicts"]
        )
        record["visual_analysis"] = None
        record.update(
            content_version=current_version + 1,
            status="pending",
            reviewer=None,
            review_note=None,
            decided_at=None,
            approval_fingerprint=None,
            approval_fingerprint_algorithm=None,
            updated_at=datetime.now(timezone.utc).isoformat(),
        )
        if record["source_conflicts"]:
            record["scan_status"] = "source_conflict"
        elif record["findings"]:
            record["scan_status"] = "findings_detected"
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
