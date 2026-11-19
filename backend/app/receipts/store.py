"""Processing facts plus the review outcome for each content version."""

from datetime import datetime, timezone
from uuid import uuid4

from app.config import DATA_DIR
from app.storage import STORE_LOCK, read_json, write_json

RECEIPTS_FILE = DATA_DIR / "receipts.json"


def load_receipts():
    return read_json(RECEIPTS_FILE, [])


def save_receipts(receipts):
    write_json(RECEIPTS_FILE, receipts)


def create_receipt(data: dict):
    with STORE_LOCK:
        receipts = load_receipts()
        receipt = {
            "receipt_id": str(uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            **data,
        }
        receipts.append(receipt)
        save_receipts(receipts)
        return receipt


def get_receipt(receipt_id: str):
    return next((r for r in load_receipts() if r["receipt_id"] == receipt_id), None)


def record_decision(
    check_id: str,
    content_version: int,
    decision: str,
    reviewer: str,
    note: str,
    seal_id: str | None = None,
    *,
    is_amendment: bool = False,
):
    now_iso = datetime.now(timezone.utc).isoformat()
    with STORE_LOCK:
        receipts = load_receipts()
        for receipt in receipts:
            if (
                receipt["check_id"] == check_id
                and receipt.get("content_version") == content_version
            ):
                receipt.update(
                    final_status=decision,
                    reviewer=reviewer,
                    review_note=note,
                    decided_at=now_iso,
                    seal_id=seal_id if decision == "approved" else None,
                )
                receipt.setdefault("decision_history", []).append(
                    {
                        "decision": decision,
                        "kind": "amended" if is_amendment else "initial",
                        "reviewer": reviewer,
                        "note": note,
                        "decided_at": now_iso,
                        "seal_id": seal_id if decision == "approved" else None,
                    }
                )
        save_receipts(receipts)
