from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.auth import get_user, require_reviewer
from app.audit.store import log_audit
from app.conflicts.store import (
    keep_unresolved,
    list_conflicts,
    resolve_conflict,
)
from app.routers.brand import recheck_after_source_resolution
from app.storage import STORE_LOCK

router = APIRouter(prefix="/api/v1/conflicts", tags=["Source conflicts"])


class ConflictResolution(BaseModel):
    selected_fact_id: str | None = Field(default=None, max_length=128)
    resolution_reason: str = Field(min_length=3, max_length=2000)

    @field_validator("resolution_reason")
    @classmethod
    def nonblank_reason(cls, value):
        value = value.strip()
        if len(value) < 3:
            raise ValueError("Provide a resolution reason of at least 3 characters")
        return value


@router.get("")
def get_conflicts(
    brand_name: str | None = None,
    status: str | None = None,
    user: dict = Depends(get_user),
):
    if status not in {None, "unresolved", "resolved"}:
        raise HTTPException(422, "Status must be unresolved or resolved")
    items = list_conflicts(brand_name, status)
    return {"conflicts": items, "total": len(items)}


@router.post("/{conflict_id}/resolve")
def resolve(
    conflict_id: str,
    body: ConflictResolution,
    user: dict = Depends(get_user),
):
    require_reviewer(user)
    try:
        with STORE_LOCK:
            if body.selected_fact_id is None:
                conflict = keep_unresolved(
                    conflict_id,
                    body.resolution_reason,
                    user["user_id"],
                )
                rechecked = []
                action = "SOURCE_CONFLICT_RETAINED_UNRESOLVED"
            else:
                conflict = resolve_conflict(
                    conflict_id,
                    body.selected_fact_id,
                    body.resolution_reason,
                    user["user_id"],
                )
                rechecked = recheck_after_source_resolution(
                    conflict["resolved_conflict_ids"],
                    user["user_id"],
                )
                action = "SOURCE_CONFLICT_RESOLVED"
            log_audit(
                action,
                user["user_id"],
                f"conflict:{conflict_id}",
                {
                    "topic_key": conflict["topic_key"],
                    "selected_fact_id": body.selected_fact_id,
                    "resolution_reason": body.resolution_reason,
                    "new_status": conflict["status"],
                    "superseded_fact_ids": conflict.get("superseded_fact_ids", []),
                    "rechecked_reviews": [item["check_id"] for item in rechecked],
                },
            )
    except LookupError as error:
        raise HTTPException(404, str(error)) from error
    except ValueError as error:
        raise HTTPException(409, str(error)) from error
    return conflict | {"rechecked_reviews": rechecked}
