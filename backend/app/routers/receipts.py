from fastapi import APIRouter, Depends, HTTPException

from app.approval.store import get_record
from app.auth import can_read, get_user, require_read_access
from app.receipts.store import get_receipt, load_receipts
from app.rules_store.store import diff_rules_snapshot, get_brand_rule_versions
from app.storage import STORE_LOCK

router = APIRouter(prefix="/api/v1/receipts", tags=["Processing Receipts"])


def receipt_view(receipt, record):
    rules = get_brand_rule_versions(record["brand_name"])
    current_rules = rules["current_version"] if rules else None
    current = (
        receipt.get("content_version") == record.get("content_version")
        and receipt["content_hash"] == record["content_hash"]
    )
    rules_current = receipt.get("rules_version") == current_rules
    rule_changes = []
    if not rules_current:
        diff = diff_rules_snapshot(
            brand_name=record["brand_name"],
            approved_brand_rules_version=receipt.get("rules_version"),
            approved_rule_versions=receipt.get("active_rule_versions"),
            channel=receipt.get("channel", "all"),
        )
        rule_changes = diff["rule_changes"]
    return {
        **receipt,
        "is_current_version": current,
        "rules_current": rules_current,
        "rule_changes": rule_changes,
        "current_review_status": record["status"],
        "approval_valid": current and rules_current and record["status"] == "approved",
    }


@router.get("/")
async def list_receipts(user: dict = Depends(get_user)):
    with STORE_LOCK:
        visible = []
        for receipt in load_receipts():
            record = get_record(receipt["check_id"])
            if record is not None and can_read(record, user):
                visible.append(receipt_view(receipt, record))
        return {"total": len(visible), "receipts": visible}


@router.get("/{receipt_id}")
async def receipt_details(receipt_id: str, user: dict = Depends(get_user)):
    with STORE_LOCK:
        receipt = get_receipt(receipt_id)
        record = get_record(receipt["check_id"]) if receipt else None
        if receipt is None or record is None:
            raise HTTPException(404, "Processing receipt not found.")
        require_read_access(record, user)
        return receipt_view(receipt, record)
