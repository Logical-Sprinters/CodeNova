"""Create, edit, check, read. The write path the whole demo rests on."""
import json

from ..core import statuses
from ..core.checker import check
from ..db import execute, fetch_all, fetch_one
from . import audit


def list_content() -> list[dict]:
    return fetch_all(
        """
        SELECT ci.content_id, ci.title, ci.channel, ci.publish_date, ci.updated_at,
               u.display_name AS creator,
               cv.version_number, cv.canonical_hash, cv.content_text,
               ap.state AS approval_state,
               (SELECT count(*) FROM findings f
                  JOIN check_runs cr ON cr.check_run_id = f.check_run_id
                 WHERE cr.content_version_id = cv.content_version_id
                   AND f.status = ANY (%(blocking)s)) AS blocking_findings,
               (SELECT count(*) FROM findings f
                  JOIN check_runs cr ON cr.check_run_id = f.check_run_id
                 WHERE cr.content_version_id = cv.content_version_id) AS total_findings
          FROM content_items ci
          JOIN users u ON u.user_id = ci.creator_id
          JOIN LATERAL (
                SELECT * FROM content_versions v
                 WHERE v.content_id = ci.content_id
                 ORDER BY v.version_number DESC LIMIT 1) cv ON TRUE
          LEFT JOIN approvals ap ON ap.content_version_id = cv.content_version_id
         ORDER BY ci.updated_at DESC
        """,
        {"blocking": list(statuses.BLOCKING)},
    )


def create(body, user: dict) -> dict:
    item = fetch_one(
        """INSERT INTO content_items (creator_id, title, channel, publish_date)
           VALUES (%s, %s, %s, %s) RETURNING content_id, channel""",
        (user["user_id"], body.title, body.channel, body.publish_date),
    )
    version = _insert_version(item["content_id"], body.text, user["user_id"])
    audit.record(item["content_id"], "USER", user["user_id"], "submitted",
                 {"version_number": version["version_number"],
                  "content_hash": version["canonical_hash"]})
    run = run_checks(version, item["channel"])
    return {"content_id": item["content_id"], "version": version, "check": run}


def add_version(content_id: str, text: str, user: dict) -> dict:
    """A new version. Any standing approval is voided by a trigger, not by this code."""
    item = fetch_one("SELECT content_id, channel FROM content_items WHERE content_id = %s",
                     (content_id,))
    if not item:
        raise LookupError("content not found")

    version = _insert_version(content_id, text, user["user_id"])
    audit.record(content_id, "USER", user["user_id"], "edited",
                 {"version_number": version["version_number"],
                  "content_hash": version["canonical_hash"]})
    run = run_checks(version, item["channel"])

    voided = fetch_one(
        "SELECT count(*) AS n FROM approvals WHERE content_id = %s AND state = 'VOID'",
        (content_id,),
    )
    return {"version": version, "check": run, "voided_approvals": voided["n"]}


def detail(content_id: str) -> dict:
    """One round trip. Everything the findings screen needs."""
    item = fetch_one(
        """SELECT ci.content_id, ci.title, ci.channel, ci.publish_date, ci.creator_id,
                  ci.created_at, ci.updated_at, u.display_name AS creator
             FROM content_items ci JOIN users u ON u.user_id = ci.creator_id
            WHERE ci.content_id = %s""",
        (content_id,),
    )
    if not item:
        raise LookupError("content not found")

    version = fetch_one(
        """SELECT content_version_id, version_number, content_text, canonical_hash,
                  created_by, created_at
             FROM content_versions WHERE content_id = %s
            ORDER BY version_number DESC LIMIT 1""",
        (content_id,),
    )
    run = fetch_one(
        """SELECT check_run_id, outcome, started_at, completed_at FROM check_runs
            WHERE content_version_id = %s ORDER BY started_at DESC LIMIT 1""",
        (version["content_version_id"],),
    )

    findings = []
    if run:
        findings = fetch_all(
            """SELECT f.finding_id, f.status, f.rule_id, f.rule_version, f.evidence_quote,
                      f.span_start, f.span_end, f.message, f.action, f.created_at,
                      r.rule_text, r.source_file, r.source_page, r.effective_from,
                      r.expires_on, r.status AS rule_status,
                      (SELECT count(*) FROM overrides o WHERE o.finding_id = f.finding_id)
                        AS override_count
                 FROM findings f
                 JOIN rules r ON (r.rule_id, r.version) = (f.rule_id, f.rule_version)
                WHERE f.check_run_id = %s
                ORDER BY f.span_start NULLS LAST, f.status""",
            (run["check_run_id"],),
        )
        for finding in findings:
            finding["rewrites"] = fetch_all(
                """SELECT option_label, strategy, rewrite_text, accepted
                     FROM finding_rewrites WHERE finding_id = %s ORDER BY option_label""",
                (finding["finding_id"],),
            )

    approval = fetch_one(
        """SELECT approval_id, state, content_hash, approved_by, approved_at, voided_at,
                  void_reason, void_diff
             FROM approvals WHERE content_id = %s ORDER BY created_at DESC LIMIT 1""",
        (content_id,),
    )

    return {**item, "version": version, "check_run": run,
            "findings": findings, "approval": approval}


def run_checks(version: dict, channel: str) -> dict:
    """Run the engine against the rules live right now, and store what it found."""
    run = fetch_one(
        """INSERT INTO check_runs (content_version_id, outcome) VALUES (%s, 'RUNNING')
           RETURNING check_run_id, started_at""",
        (version["content_version_id"],),
    )

    rules = fetch_all("SELECT * FROM live_rules_for_channel(%s, %s)",
                      (channel, run["started_at"]))
    found = check(version["content_text"], channel, rules)

    if not found:
        outcome = "COMPLETED"
    elif all(f.status == statuses.CONFLICT for f in found):
        outcome = "ABSTAINED"  # every rule that applies contradicts another: refuse to judge
    else:
        outcome = "COMPLETED"

    # Each finding and the three repairs it offers are inserted together. They are
    # kept in one tuple on purpose: an earlier version of this loop looked the
    # repairs up from a leaked loop variable and gave every price finding the
    # guarantee's wording. The demo caught it; a unit test now does too.
    pending: list[tuple[str, tuple, list[dict]]] = []
    for finding in found:
        start, end = finding.span
        quote = version["content_text"][start:end].strip() or version["content_text"][:120]
        pending.append((
            """INSERT INTO findings (check_run_id, status, rule_id, rule_version,
                                     evidence_quote, span_start, span_end, message, action)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
               RETURNING finding_id""",
            (run["check_run_id"], finding.status, finding.rule["rule_id"],
             finding.rule["version"], quote,
             start if end > start else None, end if end > start else None,
             finding.message, statuses.ACTIONS[finding.status]),
            finding.rewrites,
        ))

    from ..db import connection
    with connection() as conn, conn.cursor() as cur:
        for sql, params, options in pending:
            cur.execute(sql, params)
            finding_id = cur.fetchone()["finding_id"]
            for option in options:
                cur.execute(
                    """INSERT INTO finding_rewrites
                         (finding_id, option_label, strategy, rewrite_text)
                       VALUES (%s, %s, %s, %s)""",
                    (finding_id, option["option_label"], option["strategy"],
                     option["rewrite_text"] or "(delete this phrase)"),
                )
        cur.execute(
            "UPDATE check_runs SET outcome = %s, completed_at = now() WHERE check_run_id = %s",
            (outcome, run["check_run_id"]),
        )
        conn.commit()

    audit.record(version_content_id_to_item(version["content_version_id"]), "SYSTEM", None,
                 "checked", {"check_run_id": str(run["check_run_id"]),
                             "findings": len(found), "outcome": outcome,
                             "live_rules": len(rules)})

    return {"check_run_id": run["check_run_id"], "outcome": outcome,
            "finding_count": len(found), "live_rules_considered": len(rules),
            "findings": [{"status": f.status, "rule_id": f.rule["rule_id"],
                          "rule_version": f.rule["version"], "span": list(f.span),
                          "message": f.message} for f in found]}


def version_content_id_to_item(content_version_id: str) -> str:
    row = fetch_one("SELECT content_id FROM content_versions WHERE content_version_id = %s",
                    (content_version_id,))
    return row["content_id"]


def _insert_version(content_id: str, text: str, user_id: str) -> dict:
    """The hash is not passed in: a BEFORE INSERT trigger computes it. If that
    fails, the database is telling us something and we do not paper over it."""
    row = fetch_one(
        "SELECT COALESCE(max(version_number), 0) + 1 AS next FROM content_versions WHERE content_id = %s",
        (content_id,),
    )
    return fetch_one(
        """INSERT INTO content_versions (content_id, version_number, content_text, created_by)
           VALUES (%s, %s, %s, %s)
           RETURNING content_version_id, content_id, version_number, content_text,
                     canonical_hash, created_at""",
        (content_id, row["next"], text, user_id),
    )
