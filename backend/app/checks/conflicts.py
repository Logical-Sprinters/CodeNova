"""Source-of-truth conflict detector and admin resolution helper."""

from collections import defaultdict
import copy
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException

from app import config
from app.audit.store import log_audit
from app.checks.llm.verifier import active_facts_for_brand
from app.notifications import notify_reviewers
from app.rules_store import store as rule_store
from app.rules_store.store import load_rule_store, resolve_active_rules
from app.storage import STORE_LOCK, read_json, write_json

CONFLICTS_FILE = config.DATA_DIR / "conflicts.json"


def _conflicts_path():
    return config.DATA_DIR / "conflicts.json"


def load_conflicts() -> list[dict]:
    return read_json(_conflicts_path(), [])


def save_conflicts(items: list[dict]):
    write_json(_conflicts_path(), items)


def _norm_value(item: dict) -> str:
    cv = item.get("canonical_value")
    if isinstance(cv, str) and cv.strip():
        return "cv:" + cv.strip().casefold()
    text = item.get("rule_text") or item.get("content") or item.get("message") or ""
    return "txt:" + " ".join(text.split()).casefold()[:240]


def _clause_from_item(source_type: str, item: dict) -> dict:
    excerpt = (
        item.get("rule_text") or item.get("content") or item.get("message") or ""
    ).strip()
    return {
        "source_type": source_type,
        "source_id": item["id"],
        "title": item.get("name") or item.get("title") or item["id"],
        "version": str(item.get("version") or "1.0.0"),
        "topic_key": item.get("topic_key"),
        "canonical_value": item.get("canonical_value"),
        "effective_from": item.get("effective_from"),
        "expires_at": item.get("expires_at"),
        "channels": item.get("channels") or ["all"],
        "owner_id": item.get("owner_id") or "u2",
        "excerpt": excerpt[:400],
    }


def detect_active_conflicts(
    brand_name: str,
    check_at=None,
    channel: str = "all",
    content: str = "",
    active_rules: list[dict] | None = None,
    active_facts: list[dict] | None = None,
    persist: bool = False,
    check_id: str | None = None,
) -> list[dict]:
    """Detect contradictions among active rules and verified facts on the same topic_key."""
    if active_rules is None:
        active_rules, meta = resolve_active_rules(
            brand_name, check_at=check_at, channel=channel
        )
        effective_check_at = meta["check_at"]
    else:
        effective_check_at = str(check_at or datetime.now(timezone.utc).isoformat())

    if active_facts is None:
        active_facts = active_facts_for_brand(
            brand_name=brand_name, check_at=effective_check_at, channel=channel
        )

    # Respect cross-type supersedes links (e.g. rule superseding a fact or fact superseding a rule).
    superseded_ids = set()
    for item in list(active_rules) + list(active_facts):
        sup = item.get("supersedes")
        if sup:
            superseded_ids.add(str(sup))

    grouped: dict[str, list[tuple[str, dict]]] = defaultdict(list)
    for r in active_rules:
        key = (r.get("topic_key") or "").strip().lower()
        if not key:
            continue
        if r["id"] in superseded_ids or f"{r['id']}@{r.get('version', '1.0.0')}" in superseded_ids:
            continue
        grouped[key].append(("rule", r))

    for f in active_facts:
        key = (f.get("topic_key") or "").strip().lower()
        if not key:
            continue
        if f["id"] in superseded_ids or f"{f['id']}@{f.get('version', '1.0.0')}" in superseded_ids:
            continue
        grouped[key].append(("fact", f))

    detected = []
    for topic_key, entries in sorted(grouped.items()):
        if len(entries) < 2:
            continue
        distinct_vals = {_norm_value(item) for _, item in entries}
        if len(distinct_vals) < 2:
            continue
        clauses = [_clause_from_item(kind, item) for kind, item in entries]
        signature = "|".join(
            sorted(f"{c['source_type']}:{c['source_id']}:{c['version']}" for c in clauses)
        )
        conflict_payload = {
            "brand_name": brand_name.strip(),
            "topic_key": topic_key,
            "channel": (channel or "all").strip().lower(),
            "check_at": effective_check_at,
            "signature": signature,
            "status": "open",
            "clauses": clauses,
            "summary": (
                f"Internal conflict on topic '{topic_key}': "
                + " vs ".join(
                    f"{c['title']} ({c['canonical_value'] or c['excerpt'][:60]})"
                    for c in clauses[:3]
                )
            ),
        }
        detected.append(conflict_payload)

    if not detected or not persist:
        return detected

    with STORE_LOCK:
        existing = load_conflicts()
        now_iso = datetime.now(timezone.utc).isoformat()
        persisted = []
        for item in detected:
            match = next(
                (
                    row
                    for row in existing
                    if row.get("status") == "open"
                    and row.get("brand_name", "").strip().lower()
                    == item["brand_name"].lower()
                    and row.get("topic_key") == item["topic_key"]
                    and row.get("signature") == item["signature"]
                ),
                None,
            )
            if match is None:
                match = {
                    "conflict_id": str(uuid4()),
                    "created_at": now_iso,
                    "updated_at": now_iso,
                    "affected_check_ids": [check_id] if check_id else [],
                    "winning_source_type": None,
                    "winning_source_id": None,
                    "resolved_by": None,
                    "resolved_at": None,
                    "resolution_note": None,
                    **item,
                }
                existing.append(match)
            else:
                match["updated_at"] = now_iso
                if check_id and check_id not in match.setdefault("affected_check_ids", []):
                    match["affected_check_ids"].append(check_id)
            persisted.append(copy.deepcopy(match))
        save_conflicts(existing)
        if check_id:
            notify_reviewers(
                check_id,
                f"REVIEW PAUSED — Internal rule conflict on {brand_name} ({', '.join(c['topic_key'] for c in persisted)}).",
            )
        return persisted


def list_conflicts(
    brand_name: str | None = None,
    status: str | None = None,
) -> list[dict]:
    items = load_conflicts()
    if brand_name:
        items = [
            c
            for c in items
            if c.get("brand_name", "").strip().lower() == brand_name.strip().lower()
        ]
    if status:
        items = [c for c in items if c.get("status") == status]
    return list(reversed(items))


def get_conflict(conflict_id: str) -> dict | None:
    return next((c for c in load_conflicts() if c["conflict_id"] == conflict_id), None)


def resolve_conflict(
    conflict_id: str,
    winning_source_type: str,
    winning_source_id: str,
    actor_id: str,
    resolution_note: str = "",
) -> dict:
    with STORE_LOCK:
        conflicts = load_conflicts()
        conflict = next((c for c in conflicts if c["conflict_id"] == conflict_id), None)
        if conflict is None:
            raise HTTPException(404, "Conflict record not found")
        if conflict.get("status") != "open":
            raise HTTPException(409, "Conflict is already resolved")

        clauses = conflict.get("clauses") or []
        winner = next(
            (
                c
                for c in clauses
                if c["source_type"] == winning_source_type
                and c["source_id"] == winning_source_id
            ),
            None,
        )
        if winner is None:
            raise HTTPException(
                422,
                "winning_source_type and winning_source_id must match one of the conflicting clauses.",
            )

        now_iso = datetime.now(timezone.utc).isoformat()
        losers = [
            c
            for c in clauses
            if not (
                c["source_type"] == winning_source_type
                and c["source_id"] == winning_source_id
            )
        ]

        losing_rule_ids = {c["source_id"] for c in losers if c["source_type"] == "rule"}
        losing_fact_ids = {c["source_id"] for c in losers if c["source_type"] == "fact"}

        if losing_rule_ids:
            store = load_rule_store()
            brand_key = conflict["brand_name"].strip().lower()
            brand = store["brands"].get(brand_key)
            if brand and brand.get("current_version") in brand.get("versions", {}):
                cur_ver = brand["current_version"]
                rules = copy.deepcopy(brand["versions"][cur_ver]["rules"])
                changed_brand_rules = False
                for r in rules:
                    if r.get("id") in losing_rule_ids:
                        r["enabled"] = False
                        r["expires_at"] = now_iso
                        r["superseded_by_resolution"] = conflict_id
                        changed_brand_rules = True
                    elif (
                        winning_source_type == "rule"
                        and r.get("id") == winning_source_id
                        and len(losing_rule_ids) == 1
                        and not r.get("supersedes")
                    ):
                        r["supersedes"] = next(iter(losing_rule_ids))
                        changed_brand_rules = True
                if changed_brand_rules:
                    rev = len(brand["versions"])
                    new_ver = f"1.0.{rev}"
                    while new_ver in brand["versions"]:
                        rev += 1
                        new_ver = f"1.0.{rev}"
                    brand["versions"][new_ver] = {
                        "rules": rules,
                        "created_at": now_iso,
                    }
                    brand["current_version"] = new_ver

            # Also handle base_rules if a base rule participated in a conflict.
            if isinstance(store.get("base_rules"), list):
                for br in store["base_rules"]:
                    if br.get("id") in losing_rule_ids:
                        br["enabled"] = False
                        br["expires_at"] = now_iso
                        br["superseded_by_resolution"] = conflict_id
            write_json(rule_store.RULES_FILE, store)

        if losing_fact_ids:
            facts_path = config.DATA_DIR / "library_facts.json"
            facts = read_json(facts_path, [])
            for f in facts:
                if f.get("id") in losing_fact_ids:
                    f["enabled"] = False
                    f["expires_at"] = now_iso
                    f["superseded_by_resolution"] = conflict_id
            write_json(facts_path, facts)

        conflict.update(
            status="resolved",
            winning_source_type=winning_source_type,
            winning_source_id=winning_source_id,
            resolved_by=actor_id,
            resolved_at=now_iso,
            updated_at=now_iso,
            resolution_note=resolution_note.strip(),
        )
        save_conflicts(conflicts)
        log_audit(
            "resolve_conflict",
            actor_id,
            conflict_id,
            {
                "brand_name": conflict["brand_name"],
                "topic_key": conflict["topic_key"],
                "winning_source_type": winning_source_type,
                "winning_source_id": winning_source_id,
                "disabled_rules": sorted(losing_rule_ids),
                "disabled_facts": sorted(losing_fact_ids),
                "resolution_note": resolution_note.strip(),
            },
        )
        return copy.deepcopy(conflict)
