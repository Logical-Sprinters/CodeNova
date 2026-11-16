"""Review records, exact-text hashes and content-version snapshots."""

import hashlib
from datetime import datetime, timezone

from app.config import DATA_DIR
from app.storage import STORE_LOCK, read_json, write_json

STORE_FILE = DATA_DIR / "review_records.json"


def load_records():
    return read_json(STORE_FILE, [])


def save_records(records):
    write_json(STORE_FILE, records)


def generate_content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def snapshot(record):
    keys = (
        "content",
        "content_hash",
        "rules_version",
        "status",
        "scan_status",
        "findings",
        "reviewer",
        "review_note",
        "decided_at",
        "receipt_id",
    )
    return {
        "version": record["content_version"],
        "created_at": record["updated_at"],
        "creator_id": record["creator_id"],
        **{key: record.get(key) for key in keys},
    }


def create_record(record: dict, creator_id: str | None = None):
    with STORE_LOCK:
        if creator_id:
            record["creator_id"] = creator_id
        records = load_records()
        records.append(record)
        save_records(records)
        return record


def get_record(check_id: str):
    return next((r for r in load_records() if r["check_id"] == check_id), None)


def list_records(status: str | None = None):
    records = load_records()
    return [r for r in records if r["status"] == status] if status else records


def decide_record(check_id: str, decision: str, reviewer: str, note: str):
    with STORE_LOCK:
        records = load_records()
        record = next((r for r in records if r["check_id"] == check_id), None)
        if not record or record["status"] != "pending":
            return None
        record.update(
            status=decision,
            reviewer=reviewer,
            review_note=note,
            decided_at=datetime.now(timezone.utc).isoformat(),
        )
        if record.get("versions"):
            record["versions"][-1] = snapshot(record)
        save_records(records)
        return record


def verify_approval(
    check_id: str, brand_name: str, content: str, current_rules_version=None
):
    record = get_record(check_id)
    if not record:
        return {"valid": False, "reason": "Review record not found."}
    if record["status"] != "approved":
        return {"valid": False, "reason": "Content has not been approved."}
    if record["brand_name"].strip().lower() != brand_name.strip().lower():
        return {"valid": False, "reason": "Brand does not match."}
    if record["content_hash"] != generate_content_hash(content):
        return {"valid": False, "reason": "Content has changed since approval."}
    if record.get("rules_version") != current_rules_version:
        return {"valid": False, "reason": "Brand rules have changed since approval."}
    return {
        "valid": True,
        "reason": "Exact content and current brand rules match the approved version.",
        "check_id": check_id,
        "content_hash": record["content_hash"],
        "content_version": record["content_version"],
        "rules_version": record.get("rules_version"),
    }
