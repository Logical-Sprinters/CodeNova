"""Acting on a finding: accept one of its three repairs, or override it with a reason."""
from ..db import execute, fetch_all, fetch_one
from . import audit, content


def rewrites(finding_id: str) -> list[dict]:
    return fetch_all(
        """SELECT option_label, strategy, rewrite_text, accepted FROM finding_rewrites
            WHERE finding_id = %s ORDER BY option_label""",
        (finding_id,),
    )


def accept_rewrite(finding_id: str, option_label: str, user: dict) -> dict:
    """Accepting a rewrite is an EDIT. It creates a new immutable version, which voids
    any standing approval — exactly the same path as typing the change by hand."""
    finding = fetch_one(
        """SELECT f.finding_id, f.span_start, f.span_end, cr.content_version_id
             FROM findings f JOIN check_runs cr ON cr.check_run_id = f.check_run_id
            WHERE f.finding_id = %s""",
        (finding_id,),
    )
    if not finding:
        raise LookupError("finding not found")

    rewrite = fetch_one(
        """SELECT rewrite_id, rewrite_text, strategy, accepted FROM finding_rewrites
            WHERE finding_id = %s AND option_label = %s""",
        (finding_id, option_label.upper()),
    )
    if not rewrite:
        raise LookupError("no such rewrite option")
    if rewrite["accepted"]:
        raise ValueError({"error": "this rewrite has already been accepted"})

    version = fetch_one(
        """SELECT cv.content_id, cv.content_text, cv.version_number
             FROM content_versions cv WHERE cv.content_version_id = %s""",
        (finding["content_version_id"],),
    )

    text = version["content_text"]
    if finding["span_start"] is None:
        new_text = rewrite["rewrite_text"]
    else:
        start, end = _bounds(text, finding["span_start"], finding["span_end"],
                             rewrite["strategy"], rewrite["rewrite_text"])
        new_text = text[:start] + rewrite["rewrite_text"] + text[end:]

    if new_text.strip() == text.strip():
        raise ValueError({"error": "that rewrite leaves the copy unchanged"})

    result = content.add_version(version["content_id"], new_text, user)
    execute("UPDATE finding_rewrites SET accepted = TRUE, accepted_at = now() WHERE rewrite_id = %s",
            (rewrite["rewrite_id"],))
    return {**result, "content_id": version["content_id"], "new_text": new_text}


def _bounds(text: str, start: int, end: int, strategy: str, replacement: str) -> tuple[int, int]:
    """Where to paste the repair.

    A surgical repair replaces the matched phrase. A broader strategy replaces the
    sentence that contains it, because a bare figure dropped into the middle of a
    sentence leaves a second, worse sentence behind.
    A replacement that is itself a complete sentence must never land mid-sentence,
    so the scope follows the replacement, not only the strategy name.
    """
    if strategy == "surgical" and not replacement.endswith("."):
        return start, end

    left = max(text.rfind(". ", 0, start), text.rfind("! ", 0, start),
               text.rfind("? ", 0, start), text.rfind("\n", 0, start))
    start = 0 if left == -1 else left + 2

    candidates = [i for i in (text.find(". ", end), text.find("! ", end),
                              text.find("? ", end), text.find("\n", end)) if i != -1]
    end = min(candidates) + 1 if candidates else len(text)

    return start, end


def override(finding_id: str, body, user: dict) -> dict:
    """An override is a clarity ticket against one rule version, not a way to make a
    problem disappear quietly."""
    finding = fetch_one(
        """SELECT f.finding_id, f.rule_id, f.rule_version, cr.content_version_id
             FROM findings f JOIN check_runs cr ON cr.check_run_id = f.check_run_id
            WHERE f.finding_id = %s""",
        (finding_id,),
    )
    if not finding:
        raise LookupError("finding not found")

    content_id = content.version_content_id_to_item(finding["content_version_id"])
    row = fetch_one(
        """INSERT INTO overrides (finding_id, rule_id, rule_version, actor_id, actor_role,
                                  reason_code, reason_text)
           VALUES (%s, %s, %s, %s, %s, %s, %s)
           RETURNING override_id, created_at""",
        (finding_id, finding["rule_id"], finding["rule_version"], user["user_id"],
         user["role"], body.reason_code, body.reason_text),
    )
    audit.record(content_id, "USER", user["user_id"], "overridden", 
                 {"finding_id": str(finding_id), "rule_id": finding["rule_id"],
                  "rule_version": finding["rule_version"],
                  "reason_code": body.reason_code},
                 reason=body.reason_text)
    return {"override_id": row["override_id"], "created_at": row["created_at"]}


def clarity_tickets() -> list[dict]:
    """Rules that keep being overruled are rules that are wrong."""
    return fetch_all("SELECT * FROM v_clarity_tickets")
