"""Review records, append-only approval seals, SHA-256 tamper verification, and diffs."""

import copy
from datetime import datetime, timezone
import difflib
import hashlib
import json
import re
from uuid import uuid4

from app import config
from app.config import DATA_DIR
from app.rules_store.store import diff_rules_snapshot
from app.storage import STORE_LOCK, read_json, write_json

STORE_FILE = DATA_DIR / "review_records.json"


def _seals_path():
    return config.DATA_DIR / "approval_seals.json"


def load_records():
    return read_json(STORE_FILE, [])


def save_records(records):
    write_json(STORE_FILE, records)


def load_seals() -> list[dict]:
    return read_json(_seals_path(), [])


def save_seals(seals: list[dict]):
    write_json(_seals_path(), seals)


def generate_content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def generate_composite_hash(
    brand_name: str,
    content: str,
    asset_hashes: list[str] | None = None,
) -> str:
    canonical = json.dumps(
        {
            "brand_name": brand_name.strip().lower(),
            "content": content,
            "asset_hashes": sorted(str(h) for h in (asset_hashes or []) if h),
        },
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def compute_word_diff(approved_text: str, current_text: str) -> dict:
    """Word-and-punctuation aware diff so even a single changed comma is isolated."""
    old_tokens = re.findall(r"\w+|[^\w\s]|\s+", approved_text or "")
    new_tokens = re.findall(r"\w+|[^\w\s]|\s+", current_text or "")
    matcher = difflib.SequenceMatcher(a=old_tokens, b=new_tokens, autojunk=False)

    segments = []
    tampered_tokens = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        old_part = "".join(old_tokens[i1:i2])
        new_part = "".join(new_tokens[j1:j2])
        segments.append(
            {
                "op": tag,
                "approved_text": old_part,
                "current_text": new_part,
            }
        )
        if tag != "equal":
            if tag == "delete":
                label = f"Removed {old_part!r}"
            elif tag == "insert":
                label = f"Inserted {new_part!r}"
            else:
                label = f"{old_part!r} -> {new_part!r}"
            tampered_tokens.append(
                {
                    "op": tag,
                    "approved_text": old_part,
                    "current_text": new_part,
                    "label": label,
                }
            )

    unified = "\n".join(
        difflib.unified_diff(
            (approved_text or "").splitlines(),
            (current_text or "").splitlines(),
            fromfile="approved",
            tofile="submitted",
            lineterm="",
        )
    )
    return {
        "diff_segments": segments,
        "tampered_tokens": tampered_tokens,
        "unified_diff": unified,
    }


def snapshot(record):
    keys = (
        "content",
        "content_hash",
        "composite_hash",
        "asset_ids",
        "asset_hashes",
        "ocr_text",
        "visual_summary",
        "rules_version",
        "active_rule_versions",
        "check_at",
        "channel",
        "dropped_ungrounded_count",
        "conflicts",
        "conflict_id",
        "seal_id",
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
        now_iso = datetime.now(timezone.utc).isoformat()
        record.update(
            status=decision,
            reviewer=reviewer,
            review_note=note,
            decided_at=now_iso,
        )
        if decision == "approved":
            asset_hashes = list(record.get("asset_hashes") or [])
            composite_hash = record.get("composite_hash") or generate_composite_hash(
                record["brand_name"], record["content"], asset_hashes
            )
            seal = {
                "seal_id": str(uuid4()),
                "check_id": check_id,
                "content_version": record["content_version"],
                "brand_name": record["brand_name"],
                "snapshot_text": record["content"],
                "snapshot_asset_ids": list(record.get("asset_ids") or []),
                "snapshot_asset_hashes": sorted(asset_hashes),
                "content_hash": record["content_hash"],
                "composite_hash": composite_hash,
                "rules_version": record.get("rules_version"),
                "active_rule_versions": copy.deepcopy(
                    record.get("active_rule_versions") or {}
                ),
                "reviewer_id": reviewer,
                "sealed_at": now_iso,
            }
            seals = load_seals()
            seals.append(seal)
            save_seals(seals)
            record["seal_id"] = seal["seal_id"]
            record["composite_hash"] = composite_hash
        if record.get("versions"):
            record["versions"][-1] = snapshot(record)
        save_records(records)
        return record


def get_latest_seal(check_id: str, content_version: int | None = None) -> dict | None:
    seals = [s for s in load_seals() if s.get("check_id") == check_id]
    if content_version is not None:
        matched = [s for s in seals if s.get("content_version") == content_version]
        if matched:
            return matched[-1]
    return seals[-1] if seals else None


def verify_approval(
    check_id: str,
    brand_name: str,
    content: str,
    current_rules_version=None,
    verify_at=None,
    asset_hashes: list[str] | None = None,
):
    record = get_record(check_id)
    if not record:
        return {
            "valid": False,
            "seal_status": "NOT_APPROVED",
            "reason": "Review record not found.",
            "rule_changes": [],
            "diff_segments": [],
            "tampered_tokens": [],
        }
    if record["status"] != "approved":
        return {
            "valid": False,
            "seal_status": "NOT_APPROVED",
            "reason": (
                "Submission is paused on an internal rule conflict."
                if record["status"] == "paused_conflict"
                else "Content has not been approved."
            ),
            "rule_changes": [],
            "diff_segments": [],
            "tampered_tokens": [],
        }
    if record["brand_name"].strip().lower() != brand_name.strip().lower():
        return {
            "valid": False,
            "seal_status": "NOT_APPROVED",
            "reason": "Brand does not match.",
            "rule_changes": [],
            "diff_segments": [],
            "tampered_tokens": [],
        }

    seal = get_latest_seal(check_id, record.get("content_version"))
    approved_text = seal["snapshot_text"] if seal else record["content"]
    approved_hash = seal["content_hash"] if seal else record["content_hash"]
    approved_asset_hashes = (
        seal.get("snapshot_asset_hashes", [])
        if seal
        else list(record.get("asset_hashes") or [])
    )
    approved_composite = (
        seal["composite_hash"]
        if seal
        else generate_composite_hash(
            record["brand_name"], approved_text, approved_asset_hashes
        )
    )

    submitted_hash = generate_content_hash(content)
    submitted_asset_hashes = sorted(str(h) for h in (asset_hashes or []) if h)
    submitted_composite = generate_composite_hash(
        brand_name, content, submitted_asset_hashes
    )
    assets_mismatch = bool(approved_asset_hashes or submitted_asset_hashes) and (
        submitted_asset_hashes != sorted(approved_asset_hashes)
    )

    if approved_hash != submitted_hash or assets_mismatch:
        diff = compute_word_diff(approved_text, content)
        reason = (
            "APPROVAL VOIDED — Post-Sign-Off Tampering Detected (visual asset modified or missing)."
            if approved_hash == submitted_hash and assets_mismatch
            else "APPROVAL VOIDED — Post-Sign-Off Tampering Detected."
        )
        return {
            "valid": False,
            "seal_status": "VOIDED_TAMPERED",
            "reason": reason,
            "seal_id": seal.get("seal_id") if seal else record.get("seal_id"),
            "approved_hash": approved_hash,
            "submitted_hash": submitted_hash,
            "approved_composite_hash": approved_composite,
            "submitted_composite_hash": submitted_composite,
            "approved_asset_hashes": sorted(approved_asset_hashes),
            "submitted_asset_hashes": submitted_asset_hashes,
            "asset_tampered": assets_mismatch,
            "sealed_at": seal.get("sealed_at") if seal else record.get("decided_at"),
            "reviewer_id": seal.get("reviewer_id") if seal else record.get("reviewer"),
            "rule_changes": [],
            **diff,
        }

    diff_rules = diff_rules_snapshot(
        brand_name=record["brand_name"],
        approved_brand_rules_version=record.get("rules_version"),
        approved_rule_versions=record.get("active_rule_versions"),
        approved_rules_snapshot=record.get("active_rules_snapshot"),
        verify_at=verify_at,
        channel=record.get("channel", "all"),
    )
    if diff_rules["changed"] or (
        verify_at is None and record.get("rules_version") != current_rules_version
    ):
        return {
            "valid": False,
            "seal_status": "INVALIDATED_RULE_CHANGE",
            "reason": diff_rules["summary"],
            "seal_id": seal.get("seal_id") if seal else record.get("seal_id"),
            "approved_hash": approved_hash,
            "submitted_hash": submitted_hash,
            "rule_changes": diff_rules["rule_changes"],
            "approved_rules_version": record.get("rules_version"),
            "current_rules_version": diff_rules["current_rules_version"],
            "diff_segments": [],
            "tampered_tokens": [],
        }

    return {
        "valid": True,
        "seal_status": "SEALED",
        "reason": "SEALED — Exact content and active brand rules match the approved cryptographic hash.",
        "seal_id": seal.get("seal_id") if seal else record.get("seal_id"),
        "check_id": check_id,
        "approved_hash": approved_hash,
        "submitted_hash": submitted_hash,
        "content_hash": approved_hash,
        "composite_hash": approved_composite,
        "content_version": record["content_version"],
        "rules_version": record.get("rules_version"),
        "active_rule_versions": record.get("active_rule_versions", {}),
        "sealed_at": seal.get("sealed_at") if seal else record.get("decided_at"),
        "reviewer_id": seal.get("reviewer_id") if seal else record.get("reviewer"),
        "rule_changes": [],
        "diff_segments": [],
        "tampered_tokens": [],
    }
