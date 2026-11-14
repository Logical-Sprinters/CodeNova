
from fastapi import APIRouter, HTTPException

from app.schemas.brand import (
    ReviewDecisionRequest,
    ApprovalVerifyRequest,
)
from app.approval.store import (
    list_records,
    decide_record,
    verify_approval,
)
from app.rules_store.store import get_brand_rule_versions

router = APIRouter(tags=["Reviews and Approvals"])


@router.get("/api/v1/reviews")
async def get_reviews(status: str = None):
    return {
        "reviews": list_records(status),
        "total": len(list_records(status)),
    }


@router.patch("/api/v1/reviews/{check_id}/decision")
async def review_decision(
    check_id: str,
    request: ReviewDecisionRequest,
):

    if request.decision not in ["approved", "rejected"]:
        raise HTTPException(
            status_code=400,
            detail="Decision must be approved or rejected.",
        )

    result = decide_record(
        check_id,
        request.decision,
        request.reviewer,
        request.note,
    )

    if not result:
        raise HTTPException(
            status_code=404,
            detail="Review not found or already decided.",
        )

    return {
        "message": f"Content {request.decision}.",
        "review": result,
    }


@router.post("/api/v1/approvals/verify")
async def check_approval(request: ApprovalVerifyRequest):

    rule_data = get_brand_rule_versions(request.brand_name)
    current_version = rule_data["current_version"] if rule_data else None

    return verify_approval(
        request.check_id,
        request.brand_name,
        request.content,
        current_version,
    )
