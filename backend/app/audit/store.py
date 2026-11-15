import json
from pathlib import Path
from datetime import datetime, timezone
import uuid

AUDIT_FILE = Path(__file__).with_name('audit_log.json')

def _load_audit():
    if not AUDIT_FILE.exists():
        return []
    with open(AUDIT_FILE, 'r', encoding='utf-8') as f:
        return json.load(f)

def _save_audit(entries):
    temp = AUDIT_FILE.with_suffix('.tmp')
    with open(temp, 'w', encoding='utf-8') as f:
        json.dump(entries, f, indent=4)
    temp.replace(AUDIT_FILE)

def log_audit(action: str, actor_id: str, check_id: str, details: dict = None):
    """Append an audit entry.
    action: e.g. "create_check", "submit_version", "approve", "reject", "verify"
    details: optional dict with extra info
    """
    entry = {
        "audit_id": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "actor_id": actor_id,
        "action": action,
        "check_id": check_id,
        "details": details or {},
    }
    entries = _load_audit()
    entries.append(entry)
    _save_audit(entries)
    return entry
