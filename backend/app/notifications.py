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
    reviewer_ids = {
        u["user_id"] for u in profiles if u.get("role") in {"reviewer", "admin"}
    }
    with STORE_LOCK:
        path = config.DATA_DIR / "notifications.json"
        items = read_json(path, [])
        # Keep only one active 'review' notification per check_id so a v2 edit
        # replaces v1 instead of leaving both v1 and v2 while Review Queue shows 1 item.
        if check_id:
            items = [
                row
                for row in items
                if not (
                    row.get("check_id") == check_id
                    and row.get("type") == "review"
                    and row.get("user_id") in reviewer_ids
                )
            ]
        now_iso = datetime.now(timezone.utc).isoformat()
        for uid in reviewer_ids:
            if uid:
                items.append(
                    {
                        "id": str(uuid4()),
                        "user_id": uid,
                        "title": "Review pending",
                        "body": message,
                        "type": "review",
                        "check_id": check_id,
                        "created_at": now_iso,
                        "read": False,
                    }
                )
        write_json(path, items)


def mark_review_notifications_read(check_id: str | None):
    if not check_id:
        return
    with STORE_LOCK:
        path = config.DATA_DIR / "notifications.json"
        items = read_json(path, [])
        changed = False
        for row in items:
            if (
                row.get("check_id") == check_id
                and row.get("type") == "review"
                and not row.get("read")
            ):
                row["read"] = True
                changed = True
        if changed:
            write_json(path, items)
