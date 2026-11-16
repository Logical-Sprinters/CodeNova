from fastapi import APIRouter, Depends

from app.approval.store import list_records
from app.audit.store import load_audit
from app.auth import get_user
from app.storage import STORE_LOCK

router = APIRouter(tags=["Audit"])


@router.get("/api/v1/audit")
async def list_audit(user: dict = Depends(get_user)):
    with STORE_LOCK:
        events = load_audit()
        if user["role"] not in {"reviewer", "admin"}:
            owned = {
                r["check_id"]
                for r in list_records()
                if r.get("creator_id") == user["user_id"]
            }
            events = [event for event in events if event["check_id"] in owned]
        return {"total": len(events), "events": events}
