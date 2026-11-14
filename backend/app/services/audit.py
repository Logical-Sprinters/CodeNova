"""Writing to and reading from the append-only log."""
from ..db import fetch_all, execute


def record(content_id: str, actor_type: str, actor_id: str | None, action: str,
           details: dict | None = None, reason: str | None = None) -> None:
    """actor_type SYSTEM with actor_id NULL means the database acted. Use it for
    anything an invariant did, never for anything a person did."""
    execute(
        """INSERT INTO audit_log (content_id, actor_type, actor_id, action, reason, details)
           VALUES (%s, %s, %s, %s, %s, %s::jsonb)""",
        (content_id, actor_type, actor_id, action, reason, _json(details or {})),
    )


def ledger(content_id: str | None = None) -> list[dict]:
    return fetch_all(
        """
        SELECT a.entry_id, a.content_id, a.actor_type, a.actor_id,
               u.display_name AS actor, a.action, a.reason, a.details, a.occurred_at,
               ci.channel, ci.title
          FROM audit_log a
          JOIN content_items ci ON ci.content_id = a.content_id
          LEFT JOIN users u ON u.user_id = a.actor_id
         WHERE (%(content_id)s::text IS NULL OR a.content_id = %(content_id)s::uuid)
         ORDER BY a.occurred_at DESC, a.entry_id DESC
         LIMIT 200
        """,
        {"content_id": content_id},
    )


def _json(value: dict) -> str:
    import json
    return json.dumps(value)
