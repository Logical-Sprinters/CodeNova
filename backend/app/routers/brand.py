
from fastapi import APIRouter, HTTPException
from uuid import uuid4
from datetime import datetime, timezone

from app.schemas.brand import BrandCheckRequest, BrandCheckResponse
from app.checks.deterministic.engine import run_deterministic_checks
from app.checks.llm.verifier import run_ai_verification
from app.rules_store.store import get_brand_rule_versions
from app.approval.store import create_record, generate_content_hash
from app.receipts.store import create_receipt

router = APIRouter(
    prefix="/api/v1/brand",
    tags=["Brand Checks"],
)


@router.post("/check", response_model=BrandCheckResponse)
async def check_brand(request: BrandCheckRequest):

    findings = run_deterministic_checks(
        request.content,
        request.brand_name,
    )

    rule_data = get_brand_rule_versions(request.brand_name)
    rules_version = rule_data["current_version"] if rule_data else None

    ai_result = run_ai_verification(request.content)

    check_id = str(uuid4())
    content_hash = generate_content_hash(request.content)

    status = "pending" if findings else "completed"

    create_record({
        "check_id": check_id,
        "brand_name": request.brand_name,
        "content_hash": content_hash,
        "rules_version": rules_version,
        "status": status,
        "findings": [f.model_dump() for f in findings],
        "created_at": datetime.now(timezone.utc).isoformat(),
        "reviewer": None,
        "review_note": None,
        "decided_at": None,
    })

    receipt = create_receipt({
        "check_id": check_id,
        "brand_name": request.brand_name,
        "content_hash": content_hash,
        "rules_version": rules_version,
        "deterministic_engine": "1.0",
        "deterministic_findings": len(findings),
        "ai_verification": ai_result,
        "final_status": status,
    })

    return BrandCheckResponse(
        check_id=check_id,
        receipt_id=receipt["receipt_id"],
        brand_name=request.brand_name,
        status="review_required" if findings else "completed",
        findings=findings,
        total_findings=len(findings),
    )


@router.get("/rules/{brand_name}")
async def get_rules(brand_name: str):

    result = get_brand_rule_versions(brand_name)

    if not result:
        raise HTTPException(
            status_code=404,
            detail="Brand rules not found",
        )

    return result
