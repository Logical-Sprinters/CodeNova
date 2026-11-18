"""Reviewer finding overrides and rule clarity tickets API."""

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_user, require_reviewer
from app.overrides.store import (
    list_clarity_tickets,
    list_overrides,
    record_finding_override,
    update_clarity_ticket,
)
from app.schemas.brand import ClarityTicketUpdateRequest, FindingOverrideRequest

router = APIRouter(prefix="/api/v1", tags=["Overrides & Clarity Tickets"])


@router.post("/reviews/{check_id}/findings/{finding_id}/override")
def override_finding(
    check_id: str,
    finding_id: str,
    body: FindingOverrideRequest,
    user=Depends(get_user),
):
    require_reviewer(user)
    return record_finding_override(
        check_id=check_id,
        finding_id=finding_id,
        reason_code=body.reason_code.value,
        note=body.note,
        reviewer=user,
    )


@router.get("/overrides")
def get_overrides(
    brand_name: str | None = None,
    rule_id: str | None = None,
    rule_version: str | None = None,
    channel: str | None = None,
    reason_code: str | None = None,
    user=Depends(get_user),
):
    require_reviewer(user)
    items = list_overrides(
        brand_name=brand_name,
        rule_id=rule_id,
        rule_version=rule_version,
        channel=channel,
        reason_code=reason_code,
    )
    return {"items": items, "total": len(items)}


@router.get("/clarity-tickets")
def get_clarity_tickets(
    brand_name: str | None = None,
    rule_id: str | None = None,
    status: str | None = None,
    user=Depends(get_user),
):
    require_reviewer(user)
    if status is not None and status not in {"open", "acknowledged", "resolved"}:
        raise HTTPException(422, "status must be open, acknowledged, or resolved")
    items = list_clarity_tickets(
        brand_name=brand_name, rule_id=rule_id, status=status
    )
    return {"items": items, "total": len(items)}


@router.patch("/clarity-tickets/{ticket_id}")
def patch_clarity_ticket(
    ticket_id: str,
    body: ClarityTicketUpdateRequest,
    user=Depends(get_user),
):
    require_reviewer(user)
    ticket = update_clarity_ticket(
        ticket_id=ticket_id,
        status=body.status,
        resolution_note=body.resolution_note,
        actor_id=user["user_id"],
    )
    return {"message": "Clarity ticket updated.", "ticket": ticket}
