
import json
import hashlib
from pathlib import Path
from datetime import datetime, timezone

STORE_FILE = Path(__file__).with_name("review_records.json")


def load_records():
    if not STORE_FILE.exists():
        return []

    with open(STORE_FILE, "r", encoding="utf-8") as file:
        return json.load(file)


def save_records(records):
    temp_file = STORE_FILE.with_suffix(".tmp")

    with open(temp_file, "w", encoding="utf-8") as file:
        json.dump(records, file, indent=4)

    temp_file.replace(STORE_FILE)


def generate_content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def create_record(record: dict):
    records = load_records()
    records.append(record)
    save_records(records)


def get_record(check_id: str):
    return next(
        (r for r in load_records() if r["check_id"] == check_id),
        None,
    )


def list_records(status: str = None):
    records = load_records()

    if status:
        records = [r for r in records if r["status"] == status]

    return records


def decide_record(check_id: str, decision: str, reviewer: str, note: str):
    records = load_records()

    for record in records:
        if record["check_id"] == check_id:
            if record["status"] != "pending":
                return None

            record["status"] = decision
            record["reviewer"] = reviewer
            record["review_note"] = note
            record["decided_at"] = datetime.now(timezone.utc).isoformat()

            save_records(records)
            return record

    return None


def verify_approval(
    check_id: str,
    brand_name: str,
    content: str,
    current_rules_version: str = None,
):
    record = get_record(check_id)

    if not record:
        return {"valid": False, "reason": "Review record not found."}

    if record["status"] != "approved":
        return {"valid": False, "reason": "Content has not been approved."}

    if record["brand_name"].lower() != brand_name.strip().lower():
        return {"valid": False, "reason": "Brand does not match."}

    if record["content_hash"] != generate_content_hash(content):
        return {"valid": False, "reason": "Content has changed since approval."}

    if record["rules_version"] != current_rules_version:
        return {"valid": False, "reason": "Brand rules have changed since approval."}

    return {
        "valid": True,
        "reason": "Content and brand rules match the approved version.",
        "check_id": check_id,
        "content_hash": record["content_hash"],
    }
