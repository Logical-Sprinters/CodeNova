import json
from fastapi import APIRouter, HTTPException, Depends
from app.schemas.brand import ReviewDecisionRequest, ApprovalVerifyRequest
from app.approval.store import (
    list_records,
    decide_record,
    verify_approval,
    get_record,
)
from app.rules_store.store import get_brand_rule_versions
from app.auth import get_user
from app.audit.store import log_audit

router = APIRouter(tags=["Reviews and Approvals"])

# List all review records – any authenticated user may read
@router.get("/api/v1/reviews")
async def get_reviews(status: str = None, user: dict = Depends(get_user)):
    return {
        "reviews": list_records(status),
        "total": len(list_records(status)),
    }

# Decision endpoint – only reviewers may decide and creators cannot approve their own checks
@router.patch("/api/v1/reviews/{check_id}/decision")
async def review_decision(
    check_id: str,
    request: ReviewDecisionRequest,
    user: dict = Depends(get_user),
):
    # Role enforcement
    if user.get("role") != "reviewer":
        raise HTTPException(status_code=403, detail="Only reviewers can approve/reject")
    # Load the underlying check record to verify creator identity
    record = get_record(check_id)
    if not record:
        raise HTTPException(status_code=404, detail="Check not found")
    if record.get("creator_id") == user.get("user_id"):
        raise HTTPException(status_code=409, detail="Creators cannot approve their own submission")
    # Validate decision value
    if request.decision not in ["approved", "rejected"]:
        raise HTTPException(status_code=400, detail="Decision must be approved or rejected.")
    # Apply decision
    result = decide_record(
        check_id=check_id,
        decision=request.decision,
        reviewer=user.get("user_id"),
        note=request.note,
    )
    if not result:
        raise HTTPException(status_code=404, detail="Review not found or already decided.")
    # Audit logging for the decision
    log_audit(
        action="review_decision",
        actor_id=user.get("user_id"),
        check_id=check_id,
        details={"decision": request.decision},
    )
    return {"message": f"Content {request.decision}.", "review": result}

# Verify approval – no authentication required for prototype (could be adjusted later)
@router.post("/api/v1/approvals/verify")
async def check_approval(request: ApprovalVerifyRequest):
    rule_data = get_brand_rule_versions(request.brand_name)
    current_version = rule_data.get("current_version") if rule_data else None
    return verify_approval(
        request.check_id,
        request.brand_name,
        request.content,
        current_version,
    )
