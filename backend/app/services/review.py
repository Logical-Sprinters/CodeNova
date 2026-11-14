"""The review queue, approving, and accepting a rewrite (which is an edit)."""
from ..core import statuses
from ..core.checker import check as run_engine  # noqa: F401  (kept for symmetry of imports)
from ..db import execute, fetch_all, fetch_one
from . import audit, content


def queue() -> list[dict]:
    return fetch_all(
        """
        SELECT ci.content_id, ci.title, ci.channel, u.display_name AS creator,
               cv.version_number, cv.content_text, cv.canonical_hash,
               ap.state AS approval_state,
               (SELECT count(*) FROM findings f
                  JOIN check_runs cr ON cr.check_run_id = f.check_run_id
                 WHERE cr.content_version_id = cv.content_version_id
                   AND NOT (f.status = ANY (%(blocking)s))) AS advisory_findings
          FROM content_items ci
          JOIN users u ON u.user_id = ci.creator_id
          JOIN LATERAL (
                SELECT * FROM content_versions v WHERE v.content_id = ci.content_id
                 ORDER BY version_number DESC LIMIT 1) cv ON TRUE
          LEFT JOIN approvals ap ON ap.content_version_id = cv.content_version_id
         WHERE COALESCE(ap.state, 'DRAFT') <> 'APPROVED'
           AND NOT EXISTS (
                SELECT 1 FROM findings f
                  JOIN check_runs cr ON cr.check_run_id = f.check_run_id
                 WHERE cr.content_version_id = cv.content_version_id
                   AND f.status = ANY (%(blocking)s)
                   AND NOT EXISTS (SELECT 1 FROM overrides o WHERE o.finding_id = f.finding_id))
         ORDER BY ci.updated_at DESC
        """,
        {"blocking": list(statuses.BLOCKING)},
    )


def approve(content_id: str, user: dict) -> dict:
    """Approve the current version. The database re-checks the role, the author and
    the hash; this function only assembles the request."""
    version = fetch_one(
        """SELECT content_version_id, version_number, canonical_hash, created_by
             FROM content_versions WHERE content_id = %s
            ORDER BY version_number DESC LIMIT 1""",
        (content_id,),
    )
    if not version:
        raise LookupError("content not found")

    blocking = fetch_all(
        """
        SELECT f.finding_id, f.status, f.rule_id, f.rule_version
          FROM findings f JOIN check_runs cr ON cr.check_run_id = f.check_run_id
         WHERE cr.content_version_id = %s
           AND f.status = ANY (%s)
           AND NOT EXISTS (SELECT 1 FROM overrides o WHERE o.finding_id = f.finding_id)
        """,
        (version["content_version_id"], list(statuses.BLOCKING)),
    )
    if blocking:
        raise ValueError({
            "error": "blocking findings must be resolved first",
            "findings": [{**f, "finding_id": str(f["finding_id"])} for f in blocking],
        })

    acknowledged = fetch_all(
        """
        SELECT f.finding_id, f.status, f.rule_id
          FROM findings f JOIN check_runs cr ON cr.check_run_id = f.check_run_id
         WHERE cr.content_version_id = %s AND NOT (f.status = ANY (%s))
        """,
        (version["content_version_id"], list(statuses.BLOCKING)),
    )

    existing = fetch_one(
        "SELECT approval_id, state FROM approvals WHERE content_version_id = %s",
        (version["content_version_id"],),
    )
    if existing and existing["state"] == "APPROVED":
        raise ValueError({"error": "this version is already approved"})

    if existing:
        execute(
            """UPDATE approvals SET state = 'APPROVED', approved_by = %s, approved_at = now(),
                      voided_at = NULL, void_reason = NULL, void_diff = NULL
             WHERE approval_id = %s""",
            (user["user_id"], existing["approval_id"]),
        )
        approval_id = existing["approval_id"]
    else:
        row = fetch_one(
            """INSERT INTO approvals (content_id, content_version_id, state, content_hash,
                                      approved_by, approved_at)
               VALUES (%s, %s, 'APPROVED', %s, %s, now()) RETURNING approval_id""",
            (content_id, version["content_version_id"], version["canonical_hash"],
             user["user_id"]),
        )
        approval_id = row["approval_id"]

    audit.record(content_id, "USER", user["user_id"], "approved",
                 {"version_number": version["version_number"],
                  "content_hash": version["canonical_hash"],
                  "content_version_id": str(version["content_version_id"]),
                  "acknowledged_findings": [
                      {"finding_id": str(f["finding_id"]), "status": f["status"],
                       "rule_id": f["rule_id"]} for f in acknowledged]})

    return {"approval_id": str(approval_id), "state": "APPROVED",
            "version_number": version["version_number"],
            "content_hash": version["canonical_hash"],
            "acknowledged": [{**f, "finding_id": str(f["finding_id"])} for f in acknowledged]}
