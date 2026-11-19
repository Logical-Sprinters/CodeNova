"""Review records, exact-text hashes and content-version snapshots."""

import hashlib
import re
from difflib import SequenceMatcher
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


def generate_approval_fingerprint(record: dict) -> str:
    # Fingerprint the approved version and its approval metadata.
    import json

    payload = {
        "check_id": record.get("check_id"),
        "brand_name": record.get("brand_name"),
        "content_hash": record.get("content_hash"),
        "content_version": record.get("content_version"),
        "rules_version": record.get("rules_version"),
        "reviewer": record.get("reviewer"),
        "decided_at": record.get("decided_at"),
        "receipt_id": record.get("receipt_id"),
    }
    canonical = json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def exact_text_diff(approved: str, submitted: str) -> list[dict[str, str]]:
    approved_tokens = re.findall(r"\s+|[^\w\s]+|\w+", approved)
    submitted_tokens = re.findall(r"\s+|[^\w\s]+|\w+", submitted)
    matcher = SequenceMatcher(None, approved_tokens, submitted_tokens)
    return [
        {
            "operation": operation,
            "approved_text": "".join(approved_tokens[approved_start:approved_end]),
            "submitted_text": "".join(submitted_tokens[submitted_start:submitted_end]),
        }
        for operation, approved_start, approved_end, submitted_start, submitted_end
        in matcher.get_opcodes()
        if operation != "equal"
    ]


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
        "visual_analysis",
        "source_conflicts",
        "approval_fingerprint",
        "approval_fingerprint_algorithm",
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
        record["approval_fingerprint"] = None
        record["approval_fingerprint_algorithm"] = None
        if decision == "approved":
            record["approval_fingerprint"] = generate_approval_fingerprint(record)
            record["approval_fingerprint_algorithm"] = "SHA-256"
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
        return {
            "valid": False,
            "reason": "Content has changed since approval.",
            "text_diff": exact_text_diff(record["content"], content),
        }
    if record.get("rules_version") != current_rules_version:
        return {"valid": False, "reason": "Brand rules have changed since approval."}
    stored_fingerprint = record.get("approval_fingerprint")
    if not stored_fingerprint:
        return {
            "valid": False,
            "reason": "No approval-time SHA-256 fingerprint exists for this approval.",
        }
    expected_fingerprint = generate_approval_fingerprint(record)
    import hmac
    if not hmac.compare_digest(stored_fingerprint, expected_fingerprint):
        return {
            "valid": False,
            "reason": "Approval fingerprint mismatch. Approval metadata may have been modified.",
        }
    return {
        "valid": True,
        "reason": "Content, approval fingerprint and current brand rules match.",
        "check_id": check_id,
        "content_hash": record["content_hash"],
        "approval_fingerprint": stored_fingerprint,
        "approval_fingerprint_algorithm": record.get("approval_fingerprint_algorithm"),
        "content_version": record["content_version"],
        "rules_version": record.get("rules_version"),
    }
