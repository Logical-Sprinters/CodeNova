from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import time
from uuid import uuid4

from fastapi import APIRouter, Depends, Header, HTTPException

from app.approval.store import (
    create_record,
    generate_composite_hash,
    generate_content_hash,
    get_record,
    load_records,
    save_records,
    snapshot,
)
from app.audit.store import log_audit
from app.auth import get_user
from app.checks.conflicts import detect_active_conflicts
from app.checks.deterministic.engine import run_deterministic_checks
from app.checks.grounding import filter_grounded_findings
from app.checks.llm.verifier import (
    active_facts_for_brand,
    preflight_fact_claim_checks,
    run_ai_verification,
)
from app.checks.visual.inspector import (
    extract_dominant_colors,
    extract_image_ocr,
    inspect_visual_asset,
)
from app.notifications import notify_reviewers
from app.receipts.store import create_receipt
from app.routers.files import IMAGE_SUFFIXES, load_asset
from app.rules_store.store import get_brand_rule_versions, resolve_active_rules
from app.schemas.brand import (
    BrandCheckRequest,
    BrandCheckResponse,
    ContentVersionRequest,
    PreflightRequest,
    PreflightResponse,
)
from app.storage import STORE_LOCK

router = APIRouter(prefix="/api/v1/brand", tags=["Brand Checks"])


def resolve_assets(
    asset_ids: list[str] | None,
    user: dict,
    authorization: str = "",
) -> list[dict]:
    seen = set()
    resolved = []
    for raw_id in asset_ids or []:
        aid = str(raw_id or "").strip()
        if not aid or aid in seen:
            continue
        seen.add(aid)
        asset, raw = load_asset(aid, user, authorization)
        suffix = Path(asset["name"]).suffix.lower()
        is_image = bool(asset.get("is_image") or suffix in IMAGE_SUFFIXES)
        resolved.append(
            {
                "id": aid,
                "name": asset["name"],
                "mime": asset.get("content_type") or IMAGE_SUFFIXES.get(suffix, "application/octet-stream"),
                "is_image": is_image,
                "raw": raw,
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
        )
    return resolved


def _inspect_single_image(asset: dict, active_rules: list[dict], channel: str) -> dict:
    ocr = extract_image_ocr(asset["raw"])
    colors = extract_dominant_colors(asset["raw"])
    vis_findings = inspect_visual_asset(
        asset["raw"],
        asset["mime"],
        asset["id"],
        asset["name"],
        active_rules,
        channel=channel,
    )
    return {
        "asset_id": asset["id"],
        "name": asset["name"],
        "sha256": asset["sha256"],
        "ocr": ocr,
        "dominant_colors": colors,
        "visual_findings": vis_findings,
    }


def _merge_ai_results(caption_ai: dict, ocr_ai: dict | None) -> dict:
    if not ocr_ai or ocr_ai.get("status") == "abstained":
        return caption_ai
    if caption_ai.get("status") == "abstained":
        return ocr_ai
    status = (
        "needs_review"
        if "needs_review" in (caption_ai.get("status"), ocr_ai.get("status"))
        else "supported"
    )
    return {
        "status": status,
        "message": f"{caption_ai.get('message', '')} | OCR: {ocr_ai.get('message', '')}".strip(" |"),
        "model": caption_ai.get("model") or ocr_ai.get("model"),
        "findings": list(caption_ai.get("findings") or []) + list(ocr_ai.get("findings") or []),
        "citations": list(caption_ai.get("citations") or []) + list(ocr_ai.get("citations") or []),
        "retrieval": caption_ai.get("retrieval") or ocr_ai.get("retrieval"),
    }


def inspect_content(
    content,
    brand_name,
    check_at=None,
    channel="all",
    persist_conflicts: bool = False,
    check_id: str | None = None,
    assets: list[dict] | None = None,
):
    active_rules, meta = resolve_active_rules(
        brand_name, check_at=check_at, channel=channel
    )
    effective_check_at = meta["check_at"]
    effective_channel = meta["channel"]
    active_facts = active_facts_for_brand(
        brand_name=brand_name, check_at=effective_check_at, channel=effective_channel
    )
    rules = get_brand_rule_versions(brand_name)

    resolved_assets = assets or []
    asset_ids = [a["id"] for a in resolved_assets]
    asset_hashes = [a["sha256"] for a in resolved_assets]
    image_assets = [a for a in resolved_assets if a.get("is_image")]

    content_hash = generate_content_hash(content)
    composite_hash = generate_composite_hash(brand_name, content, asset_hashes)

    # Parallel Pass 1: caption deterministic checks + per-image OCR/color/visual analysis.
    with ThreadPoolExecutor(max_workers=4) as pool:
        cap_det_fut = pool.submit(
            lambda: [
                f.model_dump()
                for f in run_deterministic_checks(
                    content,
                    brand_name,
                    check_at=effective_check_at,
                    channel=effective_channel,
                    source_origin="caption",
                    active_rules=active_rules,
                )
            ]
        )
        img_futs = [
            pool.submit(_inspect_single_image, asset, active_rules, effective_channel)
            for asset in image_assets
        ]
        caption_det = cap_det_fut.result()
        image_results = [fut.result() for fut in img_futs]

    ocr_parts = [
        res["ocr"]["text"].strip()
        for res in image_results
        if res["ocr"]["text"].strip()
    ]
    combined_ocr_text = "\n".join(ocr_parts)
    visual_summary = [
        {
            "asset_id": res["asset_id"],
            "name": res["name"],
            "sha256": res["sha256"],
            "width": res["ocr"]["width"],
            "height": res["ocr"]["height"],
            "ocr_status": res["ocr"]["ocr_status"],
            "ocr_text": res["ocr"]["text"],
            "dominant_colors": res["dominant_colors"],
        }
        for res in image_results
    ]
    visual_findings = [
        f for res in image_results for f in res["visual_findings"]
    ]

    conflict_probe = f"{content}\n{combined_ocr_text}".strip()
    conflicts = detect_active_conflicts(
        brand_name=brand_name,
        check_at=effective_check_at,
        channel=effective_channel,
        content=conflict_probe,
        active_rules=active_rules,
        active_facts=active_facts,
        persist=persist_conflicts,
        check_id=check_id,
    )
    if conflicts:
        return {
            "content": content,
            "content_hash": content_hash,
            "composite_hash": composite_hash,
            "asset_ids": asset_ids,
            "asset_hashes": sorted(asset_hashes),
            "ocr_text": combined_ocr_text,
            "visual_summary": visual_summary,
            "rules_version": rules["current_version"] if rules else None,
            "check_at": effective_check_at,
            "channel": effective_channel,
            "active_rule_versions": meta["active_rule_versions"],
            "active_rules_snapshot": [
                {
                    "id": r["id"],
                    "name": r["name"],
                    "version": r["version"],
                    "rule_text": r["rule_text"],
                }
                for r in active_rules
            ],
            "findings": [],
            "dropped_ungrounded_count": 0,
            "dropped_ungrounded_reasons": [],
            "deterministic_count": 0,
            "scan_status": "abstained_conflict",
            "conflicts": conflicts,
            "conflict_id": conflicts[0].get("conflict_id"),
            "ai_verification": {
                "status": "abstained",
                "message": "REVIEW PAUSED — INTERNAL RULE CONFLICT detected. Abstained from emitting findings.",
                "findings": [],
                "citations": [],
            },
        }

    # Parallel Pass 2: caption AI verification + OCR deterministic/AI verification.
    with ThreadPoolExecutor(max_workers=4) as pool:
        cap_ai_fut = pool.submit(
            run_ai_verification,
            content,
            brand_facts=active_facts,
            brand_name=brand_name,
            check_at=effective_check_at,
            channel=effective_channel,
            source_origin="caption",
        )
        ocr_det_fut = (
            pool.submit(
                lambda: [
                    f.model_dump()
                    for f in run_deterministic_checks(
                        combined_ocr_text,
                        brand_name,
                        check_at=effective_check_at,
                        channel=effective_channel,
                        source_origin="image_ocr",
                        active_rules=active_rules,
                    )
                ]
            )
            if combined_ocr_text
            else None
        )
        ocr_ai_fut = (
            pool.submit(
                run_ai_verification,
                combined_ocr_text,
                brand_facts=active_facts,
                brand_name=brand_name,
                check_at=effective_check_at,
                channel=effective_channel,
                source_origin="image_ocr",
            )
            if combined_ocr_text
            else None
        )
        caption_ai = cap_ai_fut.result()
        ocr_det = ocr_det_fut.result() if ocr_det_fut else []
        ocr_ai = ocr_ai_fut.result() if ocr_ai_fut else None

    ai_result = _merge_ai_results(caption_ai, ocr_ai)
    raw_findings = (
        caption_det
        + caption_ai.get("findings", [])
        + ocr_det
        + (ocr_ai.get("findings", []) if ocr_ai else [])
        + visual_findings
    )
    grounded_findings, dropped = filter_grounded_findings(
        raw_findings,
        active_rules,
        content,
        active_facts=active_facts,
        ocr_text=combined_ocr_text,
    )
    return {
        "content": content,
        "content_hash": content_hash,
        "composite_hash": composite_hash,
        "asset_ids": asset_ids,
        "asset_hashes": sorted(asset_hashes),
        "ocr_text": combined_ocr_text,
        "visual_summary": visual_summary,
        "rules_version": rules["current_version"] if rules else None,
        "check_at": effective_check_at,
        "channel": effective_channel,
        "active_rule_versions": meta["active_rule_versions"],
        "active_rules_snapshot": [
            {
                "id": r["id"],
                "name": r["name"],
                "version": r["version"],
                "rule_text": r["rule_text"],
            }
            for r in active_rules
        ],
        "findings": grounded_findings,
        "dropped_ungrounded_count": len(dropped),
        "dropped_ungrounded_reasons": [d["drop_reason"] for d in dropped],
        "deterministic_count": sum(
            1 for f in grounded_findings if not f["rule_id"].startswith("AI-")
        ),
        "scan_status": "findings_detected" if grounded_findings else "passed",
        "conflicts": [],
        "conflict_id": None,
        "ai_verification": ai_result,
    }


def attach_receipt(record):
    receipt = create_receipt(
        {
            "check_id": record["check_id"],
            "creator_id": record["creator_id"],
            "brand_name": record["brand_name"],
            "content_hash": record["content_hash"],
            "composite_hash": record.get("composite_hash"),
            "asset_ids": record.get("asset_ids", []),
            "asset_hashes": record.get("asset_hashes", []),
            "content_version": record["content_version"],
            "rules_version": record["rules_version"],
            "check_at": record.get("check_at"),
            "channel": record.get("channel", "all"),
            "active_rule_versions": record.get("active_rule_versions", {}),
            "dropped_ungrounded_count": record.get("dropped_ungrounded_count", 0),
            "conflict_id": record.get("conflict_id"),
            "seal_id": record.get("seal_id"),
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
    is_conflict = record["status"] == "paused_conflict"
    return BrandCheckResponse(
        check_id=record["check_id"],
        receipt_id=record["receipt_id"],
        brand_name=record["brand_name"],
        status="review_paused_conflict" if is_conflict else "review_required",
        findings=record["findings"],
        total_findings=len(record["findings"]),
        content_version=record["content_version"],
        scan_status=record["scan_status"],
        review_status=record["status"],
        rules_version=record.get("rules_version"),
        check_at=record.get("check_at"),
        channel=record.get("channel", "all"),
        active_rule_versions=record.get("active_rule_versions", {}),
        dropped_ungrounded_count=record.get("dropped_ungrounded_count", 0),
        conflicts=record.get("conflicts", []),
        conflict_id=record.get("conflict_id"),
        asset_ids=record.get("asset_ids", []),
        ocr_text=record.get("ocr_text", ""),
        visual_summary=record.get("visual_summary", []),
        ai_verification=record.get("ai_verification"),
    )


@router.post("/preflight", response_model=PreflightResponse)
async def preflight_brand_check(
    request: PreflightRequest,
    user: dict = Depends(get_user),
    authorization: str = Header(default=""),
):
    """Stateless Shift-Left pre-flight check: zero database writes or notifications."""
    started = time.perf_counter()
    resolved_assets = resolve_assets(request.asset_ids, user, authorization)
    image_assets = [a for a in resolved_assets if a.get("is_image")]

    active_rules, meta = resolve_active_rules(
        request.brand_name, check_at=request.check_at, channel=request.channel
    )
    effective_check_at = meta["check_at"]
    effective_channel = meta["channel"]
    active_facts = active_facts_for_brand(
        brand_name=request.brand_name,
        check_at=effective_check_at,
        channel=effective_channel,
    )

    with ThreadPoolExecutor(max_workers=4) as pool:
        cap_det_fut = pool.submit(
            lambda: [
                f.model_dump()
                for f in run_deterministic_checks(
                    request.content,
                    request.brand_name,
                    check_at=effective_check_at,
                    channel=effective_channel,
                    source_origin="caption",
                    active_rules=active_rules,
                )
            ]
        )
        cap_fact_fut = pool.submit(
            preflight_fact_claim_checks,
            request.content,
            brand_name=request.brand_name,
            check_at=effective_check_at,
            channel=effective_channel,
            active_facts=active_facts,
            source_origin="caption",
        )
        img_futs = [
            pool.submit(_inspect_single_image, asset, active_rules, effective_channel)
            for asset in image_assets
        ]
        det_findings = cap_det_fut.result()
        fact_findings = cap_fact_fut.result()
        image_results = [fut.result() for fut in img_futs]

    combined_ocr_text = "\n".join(
        res["ocr"]["text"].strip()
        for res in image_results
        if res["ocr"]["text"].strip()
    )
    visual_summary = [
        {
            "asset_id": res["asset_id"],
            "name": res["name"],
            "sha256": res["sha256"],
            "width": res["ocr"]["width"],
            "height": res["ocr"]["height"],
            "ocr_status": res["ocr"]["ocr_status"],
            "ocr_text": res["ocr"]["text"],
            "dominant_colors": res["dominant_colors"],
        }
        for res in image_results
    ]
    visual_findings = [
        f for res in image_results for f in res["visual_findings"]
    ]

    conflict_probe = f"{request.content}\n{combined_ocr_text}".strip()
    conflicts = detect_active_conflicts(
        brand_name=request.brand_name,
        check_at=effective_check_at,
        channel=effective_channel,
        content=conflict_probe,
        active_rules=active_rules,
        active_facts=active_facts,
        persist=False,
    )
    if conflicts:
        elapsed = round((time.perf_counter() - started) * 1000, 2)
        return PreflightResponse(
            status="conflict_detected",
            brand_name=request.brand_name,
            channel=effective_channel,
            check_at=effective_check_at,
            findings=[],
            total_findings=0,
            conflicts=conflicts,
            asset_ids=[a["id"] for a in resolved_assets],
            ocr_text=combined_ocr_text,
            visual_summary=visual_summary,
            elapsed_ms=elapsed,
        )

    ocr_det = []
    ocr_facts = []
    if combined_ocr_text:
        ocr_det = [
            f.model_dump()
            for f in run_deterministic_checks(
                combined_ocr_text,
                request.brand_name,
                check_at=effective_check_at,
                channel=effective_channel,
                source_origin="image_ocr",
                active_rules=active_rules,
            )
        ]
        ocr_facts = preflight_fact_claim_checks(
            combined_ocr_text,
            brand_name=request.brand_name,
            check_at=effective_check_at,
            channel=effective_channel,
            active_facts=active_facts,
            source_origin="image_ocr",
        )

    grounded, _ = filter_grounded_findings(
        det_findings + fact_findings + ocr_det + ocr_facts + visual_findings,
        active_rules,
        request.content,
        active_facts=active_facts,
        ocr_text=combined_ocr_text,
    )
    elapsed = round((time.perf_counter() - started) * 1000, 2)
    return PreflightResponse(
        status="warnings_detected" if grounded else "clean",
        brand_name=request.brand_name,
        channel=effective_channel,
        check_at=effective_check_at,
        findings=grounded,
        total_findings=len(grounded),
        conflicts=[],
        asset_ids=[a["id"] for a in resolved_assets],
        ocr_text=combined_ocr_text,
        visual_summary=visual_summary,
        elapsed_ms=elapsed,
    )


@router.post("/check", response_model=BrandCheckResponse)
async def check_brand(
    request: BrandCheckRequest,
    user: dict = Depends(get_user),
    authorization: str = Header(default=""),
):
    with STORE_LOCK:
        now = datetime.now(timezone.utc).isoformat()
        new_check_id = str(uuid4())
        resolved_assets = resolve_assets(request.asset_ids, user, authorization)
        inspection = inspect_content(
            request.content,
            request.brand_name,
            check_at=request.check_at,
            channel=request.channel,
            persist_conflicts=True,
            check_id=new_check_id,
            assets=resolved_assets,
        )
        initial_status = (
            "paused_conflict" if inspection.get("conflicts") else "pending"
        )
        record = {
            "check_id": new_check_id,
            "brand_name": request.brand_name,
            "creator_id": user["user_id"],
            "content_version": 1,
            "created_at": now,
            "updated_at": now,
            "status": initial_status,
            "reviewer": None,
            "review_note": None,
            "decided_at": None,
            **inspection,
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
                "composite_hash": record.get("composite_hash"),
                "asset_ids": record.get("asset_ids", []),
                "rules_version": record["rules_version"],
                "check_at": record.get("check_at"),
                "channel": record.get("channel", "all"),
                "dropped_ungrounded_count": record.get("dropped_ungrounded_count", 0),
                "conflict_id": record.get("conflict_id"),
                "scan_status": record["scan_status"],
                "receipt_id": record["receipt_id"],
            },
        )
        if initial_status == "pending":
            notify_reviewers(
                record["check_id"],
                f"{record['brand_name']} content v{record['content_version']} awaits review.",
            )
        return response_for(record)


@router.post("/{check_id}/versions", response_model=BrandCheckResponse)
async def submit_version(
    check_id: str,
    request: ContentVersionRequest,
    user: dict = Depends(get_user),
    authorization: str = Header(default=""),
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
        target_asset_ids = (
            request.asset_ids
            if request.asset_ids is not None
            else list(record.get("asset_ids") or [])
        )
        resolved_assets = resolve_assets(target_asset_ids, user, authorization)
        # Re-run the real checker and fetch the active rules at check_at on every edit.
        inspection = inspect_content(
            request.content,
            record["brand_name"],
            check_at=request.check_at,
            channel=request.channel or record.get("channel", "all"),
            persist_conflicts=True,
            check_id=check_id,
            assets=resolved_assets,
        )
        new_status = "paused_conflict" if inspection.get("conflicts") else "pending"
        record.update(inspection)
        record.update(
            content_version=current_version + 1,
            status=new_status,
            reviewer=None,
            review_note=None,
            decided_at=None,
            seal_id=None,
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
                "asset_ids": record.get("asset_ids", []),
                "rules_version": record["rules_version"],
                "check_at": record.get("check_at"),
                "channel": record.get("channel", "all"),
                "dropped_ungrounded_count": record.get("dropped_ungrounded_count", 0),
                "conflict_id": record.get("conflict_id"),
                "scan_status": record["scan_status"],
                "receipt_id": record["receipt_id"],
                "previous_status": old_status,
                "approval_invalidated": old_status == "approved",
            },
        )
        if new_status == "pending":
            notify_reviewers(
                record["check_id"],
                f"{record['brand_name']} content v{record['content_version']} awaits review.",
            )
        return response_for(record)


@router.get("/rules/{brand_name}")
async def get_rules(brand_name: str, as_of: str | None = None, channel: str = "all"):
    result = get_brand_rule_versions(brand_name)
    if not result:
        raise HTTPException(404, "Brand rules not found")
    active, meta = resolve_active_rules(brand_name, check_at=as_of, channel=channel)
    return {
        **result,
        "check_at": meta["check_at"],
        "channel": meta["channel"],
        "active_rule_versions": meta["active_rule_versions"],
        "active_rules": [
            {
                "id": r["id"],
                "name": r["name"],
                "version": r["version"],
                "rule_type": r.get("rule_type", "regex"),
                "rule_text": r["rule_text"],
                "effective_from": r.get("effective_from"),
                "expires_at": r.get("expires_at"),
                "supersedes": r.get("supersedes"),
                "topic_key": r.get("topic_key"),
                "canonical_value": r.get("canonical_value"),
            }
            for r in active
        ],
    }
