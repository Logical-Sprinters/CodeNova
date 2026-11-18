"""Admin/reviewer source-of-truth conflict queue and resolution API."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException

from app.approval.store import load_records, save_records, snapshot
from app.auth import get_user, require_reviewer
from app.checks.conflicts import get_conflict, list_conflicts, resolve_conflict
from app.routers.brand import attach_receipt, inspect_content, resolve_assets
from app.schemas.brand import ConflictResolveRequest
from app.storage import STORE_LOCK

router = APIRouter(prefix="/api/v1/conflicts", tags=["Rule Conflicts"])


@router.get("")
@router.get("/")
def get_all_conflicts(
    brand_name: str | None = None,
    status: str | None = None,
    user=Depends(get_user),
):
    if status is not None and status not in {"open", "resolved"}:
        raise HTTPException(422, "status must be 'open' or 'resolved'")
    items = list_conflicts(brand_name=brand_name, status=status)
    return {"items": items, "total": len(items)}


@router.get("/{conflict_id}")
def read_conflict(conflict_id: str, user=Depends(get_user)):
    item = get_conflict(conflict_id)
    if item is None:
        raise HTTPException(404, "Conflict not found")
    return item


@router.post("/{conflict_id}/resolve")
def resolve_active_conflict(
    conflict_id: str,
    body: ConflictResolveRequest,
    user=Depends(get_user),
    authorization: str = Header(default=""),
):
    require_reviewer(user)
    with STORE_LOCK:
        resolved = resolve_conflict(
            conflict_id=conflict_id,
            winning_source_type=body.winning_source_type,
            winning_source_id=body.winning_source_id,
            actor_id=user["user_id"],
            resolution_note=body.resolution_note,
        )
        updated_checks = []
        if body.auto_recheck:
            records = load_records()
            changed = False
            for rec in records:
                if (
                    rec.get("status") == "paused_conflict"
                    and (
                        rec.get("conflict_id") == conflict_id
                        or rec["check_id"] in resolved.get("affected_check_ids", [])
                    )
                ):
                    rec_assets = (
                        resolve_assets(rec.get("asset_ids"), user, authorization)
                        if rec.get("asset_ids")
                        else []
                    )
                    inspection = inspect_content(
                        rec["content"],
                        rec["brand_name"],
                        check_at=rec.get("check_at"),
                        channel=rec.get("channel", "all"),
                        persist_conflicts=True,
                        check_id=rec["check_id"],
                        assets=rec_assets,
                    )
                    still_conflicted = bool(inspection.get("conflicts"))
                    rec.update(inspection)
                    rec.update(
                        status="paused_conflict" if still_conflicted else "pending",
                        updated_at=datetime.now(timezone.utc).isoformat(),
                    )
                    attach_receipt(rec)
                    if rec.get("versions"):
                        rec["versions"][-1] = snapshot(rec)
                    updated_checks.append(
                        {
                            "check_id": rec["check_id"],
                            "status": rec["status"],
                            "scan_status": rec["scan_status"],
                            "total_findings": len(rec["findings"]),
                            "receipt_id": rec["receipt_id"],
                        }
                    )
                    changed = True
            if changed:
                save_records(records)
        return {
            "message": "Conflict resolved and winning source pinned.",
            "conflict": resolved,
            "updated_checks": updated_checks,
        }
