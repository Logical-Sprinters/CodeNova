from datetime import datetime, timezone
from uuid import uuid4
from app import config
from app.storage import STORE_LOCK, read_json, write_json


def notify(user_ids, title, body, kind="review", check_id=None):
    with STORE_LOCK:
        path = config.DATA_DIR / "notifications.json"
        items = read_json(path, [])
        for uid in set(user_ids):
            if uid:
                items.append(
                    {
                        "id": str(uuid4()),
                        "user_id": uid,
                        "title": title,
                        "body": body,
                        "type": kind,
                        "check_id": check_id,
                        "created_at": datetime.now(timezone.utc).isoformat(),
                        "read": False,
                    }
                )
        write_json(path, items)


def notify_reviewers(check_id, message):
    profiles = read_json(config.DATA_DIR / "users.json", [])
    notify(
        [u["user_id"] for u in profiles if u.get("role") in {"reviewer", "admin"}],
        "Review pending",
        message,
        check_id=check_id,
    )
