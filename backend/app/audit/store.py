"""Local JSON audit events (not a tamper-proof compliance ledger)."""

from datetime import datetime, timezone
from uuid import uuid4

from app.config import DATA_DIR
from app.storage import STORE_LOCK, read_json, write_json

AUDIT_FILE = DATA_DIR / "audit_log.json"


def load_audit():
    return read_json(AUDIT_FILE, [])


def log_audit(action: str, actor_id: str, check_id: str, details: dict | None = None):
    with STORE_LOCK:
        entry = {
            "audit_id": str(uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "actor_id": actor_id,
            "action": action,
            "check_id": check_id,
            "details": details or {},
        }
        entries = load_audit()
        entries.append(entry)
        write_json(AUDIT_FILE, entries)
        return entry
