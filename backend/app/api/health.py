from fastapi import APIRouter

from ..db import fetch_one

router = APIRouter(tags=["system"])


@router.get("/health", summary="Is the API up, and is the database seeded?")
def health():
    row = fetch_one(
        """
        SELECT (SELECT count(*) FROM users)            AS users,
               (SELECT count(*) FROM rules)            AS rule_versions,
               (SELECT count(*) FROM v_live_rules)     AS live_rules_now,
               (SELECT count(*) FROM content_items)    AS content_items,
               (SELECT count(*) FROM findings)         AS findings,
               (SELECT count(*) FROM audit_log)        AS audit_entries,
               current_date                            AS server_date
        """
    )
    return {"status": "ok", "database": "reachable", **row}
