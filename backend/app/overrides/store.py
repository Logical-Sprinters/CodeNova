"""Coded override telemetry and friction-based clarity ticket aggregation.

Hard invariant: override telemetry NEVER automatically mutates any brand rule.
"""

from collections import Counter
import copy
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException

from app import config
from app.approval.store import load_records, save_records, snapshot
from app.audit.store import log_audit
from app.checks.grounding import filter_grounded_findings
from app.checks.llm.verifier import active_facts_for_brand
from app.notifications import notify
from app.rules_store.store import get_base_rules, load_rule_store, resolve_active_rules
from app.storage import STORE_LOCK, read_json, write_json


def _overrides_path():
    return config.DATA_DIR / "finding_overrides.json"


def _tickets_path():
    return config.DATA_DIR / "clarity_tickets.json"


def load_overrides() -> list[dict]:
    return read_json(_overrides_path(), [])


def save_overrides(items: list[dict]):
    write_json(_overrides_path(), items)


def load_clarity_tickets() -> list[dict]:
    return read_json(_tickets_path(), [])


def save_clarity_tickets(items: list[dict]):
    write_json(_tickets_path(), items)


def _lookup_rule_owner(brand_name: str, rule_id: str) -> str:
    try:
        store = load_rule_store()
        brand = store["brands"].get(brand_name.strip().lower())
        if brand:
            cur = brand.get("current_version")
            for r in brand.get("versions", {}).get(cur, {}).get("rules", []):
                if r.get("id") == rule_id and r.get("owner_id"):
                    return str(r["owner_id"])
        for br in get_base_rules(store):
            if br.get("id") == rule_id and br.get("owner_id"):
                return str(br["owner_id"])
    except HTTPException:
        pass
    return "u2"


def _upsert_clarity_ticket(
    *,
    brand_name: str,
    rule_id: str,
    rule_version: str,
    ticket_channel: str,
    matching_overrides: list[dict],
    owner_id: str,
    now_iso: str,
) -> dict:
    tickets = load_clarity_tickets()
    existing = next(
        (
            t
            for t in tickets
            if t.get("status") in {"open", "acknowledged"}
            and t.get("brand_name", "").strip().lower() == brand_name.strip().lower()
            and t.get("rule_id") == rule_id
            and str(t.get("rule_version")) == str(rule_version)
            and t.get("channel") == ticket_channel
        ),
        None,
    )
    breakdown = dict(Counter(o["reason_code"] for o in matching_overrides))
    channels_affected = sorted({o.get("channel", "all") for o in matching_overrides})
    samples = [
        {
            "override_id": o["override_id"],
            "check_id": o["check_id"],
            "channel": o.get("channel", "all"),
            "reason_code": o["reason_code"],
            "note": o.get("note", ""),
            "reviewer_id": o["reviewer_id"],
            "created_at": o["created_at"],
        }
        for o in matching_overrides[-5:]
    ]
    if existing is not None:
        existing.update(
            override_count=len(matching_overrides),
            reason_breakdown=breakdown,
            channels_affected=channels_affected,
            sample_overrides=samples,
            updated_at=now_iso,
        )
        save_clarity_tickets(tickets)
        return copy.deepcopy(existing)

    ticket = {
        "ticket_id": str(uuid4()),
        "brand_name": brand_name.strip(),
        "rule_id": rule_id,
        "rule_version": str(rule_version),
        "channel": ticket_channel,
        "channels_affected": channels_affected,
        "owner_id": owner_id,
        "override_count": len(matching_overrides),
        "reason_breakdown": breakdown,
        "sample_overrides": samples,
        "status": "open",
        "resolution_note": "",
        "auto_mutated_rule": False,
        "created_at": now_iso,
        "updated_at": now_iso,
    }
    tickets.append(ticket)
    save_clarity_tickets(tickets)
    notify(
        [owner_id],
        "Rule clarity ticket opened",
        (
            f"Rule {rule_id} (v{rule_version}) on {brand_name} "
            f"[{ticket_channel}] hit {len(matching_overrides)} coded overrides."
        ),
        kind="clarity_ticket",
        check_id=ticket["ticket_id"],
    )
    return copy.deepcopy(ticket)


def record_finding_override(
    *,
    check_id: str,
    finding_id: str,
    reason_code: str,
    note: str,
    reviewer: dict,
) -> dict:
    with STORE_LOCK:
        records = load_records()
        record = next((r for r in records if r["check_id"] == check_id), None)
        if record is None:
            raise HTTPException(404, "Check not found")
        if record.get("creator_id") == reviewer["user_id"]:
            raise HTTPException(409, "Creators cannot override findings on their own submission")
        if record.get("status") == "paused_conflict":
            raise HTTPException(409, "Resolve the internal rule conflict before overriding findings")

        # Verify findings server-side first so reviewers cannot override an ungrounded finding.
        brand_name = record["brand_name"]
        check_at = record.get("check_at") or record.get("created_at")
        channel = record.get("channel", "all")
        store = load_rule_store()
        brand = store["brands"].get(brand_name.strip().lower())
        version_override = (
            record.get("rules_version")
            if brand and record.get("rules_version") in brand.get("versions", {})
            else None
        )
        active_rules, _ = resolve_active_rules(
            brand_name,
            check_at=check_at,
            channel=channel,
            version_override=version_override,
        )
        active_facts = active_facts_for_brand(
            brand_name=brand_name, check_at=check_at, channel=channel
        )
        grounded, _ = filter_grounded_findings(
            record.get("findings", []),
            active_rules,
            record.get("content", ""),
            active_facts=active_facts,
        )
        target = next((f for f in grounded if f.get("finding_id") == finding_id), None)
        if target is None:
            raise HTTPException(404, "Grounded finding not found on this submission")

        overrides = load_overrides()
        if any(
            o.get("check_id") == check_id
            and o.get("content_version") == record["content_version"]
            and o.get("finding_id") == finding_id
            for o in overrides
        ):
            raise HTTPException(409, "This finding has already been overridden for this version")

        now_iso = datetime.now(timezone.utc).isoformat()
        rule_id = target["rule_id"]
        rule_version = str(target.get("rule_version") or "1.0.0")
        effective_channel = (target.get("channel") or channel or "all").strip().lower()

        override = {
            "override_id": str(uuid4()),
            "check_id": check_id,
            "content_version": record["content_version"],
            "finding_id": finding_id,
            "brand_name": brand_name,
            "channel": effective_channel,
            "rule_id": rule_id,
            "rule_version": rule_version,
            "reason_code": reason_code,
            "note": note.strip(),
            "reviewer_id": reviewer["user_id"],
            "created_at": now_iso,
        }
        overrides.append(override)
        save_overrides(overrides)

        # Annotate the finding on the stored review record without deleting evidence.
        for f in record.get("findings", []):
            if f.get("finding_id") == finding_id:
                f["overridden"] = True
                f["override"] = {
                    "override_id": override["override_id"],
                    "reason_code": reason_code,
                    "note": override["note"],
                    "reviewer_id": reviewer["user_id"],
                    "created_at": now_iso,
                }
        record["updated_at"] = now_iso
        if record.get("versions"):
            record["versions"][-1] = snapshot(record)
        save_records(records)

        log_audit(
            "override_finding",
            reviewer["user_id"],
            check_id,
            {
                "override_id": override["override_id"],
                "finding_id": finding_id,
                "rule_id": rule_id,
                "rule_version": rule_version,
                "channel": effective_channel,
                "reason_code": reason_code,
                "content_version": record["content_version"],
            },
        )

        # Aggregate friction telemetry -> Clarity Ticket (ZERO automatic rule mutation).
        threshold = config.OVERRIDE_FRICTION_THRESHOLD
        owner_id = _lookup_rule_owner(brand_name, rule_id)
        same_rule_version = [
            o
            for o in overrides
            if o.get("brand_name", "").strip().lower() == brand_name.strip().lower()
            and o.get("rule_id") == rule_id
            and str(o.get("rule_version")) == str(rule_version)
        ]
        same_channel = [
            o for o in same_rule_version if o.get("channel") == effective_channel
        ]
        clarity_ticket = None
        if len(same_channel) >= threshold:
            clarity_ticket = _upsert_clarity_ticket(
                brand_name=brand_name,
                rule_id=rule_id,
                rule_version=rule_version,
                ticket_channel=effective_channel,
                matching_overrides=same_channel,
                owner_id=owner_id,
                now_iso=now_iso,
            )
        elif len(same_rule_version) >= threshold:
            clarity_ticket = _upsert_clarity_ticket(
                brand_name=brand_name,
                rule_id=rule_id,
                rule_version=rule_version,
                ticket_channel="multi",
                matching_overrides=same_rule_version,
                owner_id=owner_id,
                now_iso=now_iso,
            )

        return {
            "message": "Finding overridden with coded reason.",
            "override": override,
            "clarity_ticket": clarity_ticket,
            "rules_mutated": False,
        }


def list_overrides(
    brand_name: str | None = None,
    rule_id: str | None = None,
    rule_version: str | None = None,
    channel: str | None = None,
    reason_code: str | None = None,
) -> list[dict]:
    items = load_overrides()
    if brand_name:
        items = [
            o
            for o in items
            if o.get("brand_name", "").strip().lower() == brand_name.strip().lower()
        ]
    if rule_id:
        items = [o for o in items if o.get("rule_id") == rule_id]
    if rule_version:
        items = [o for o in items if str(o.get("rule_version")) == str(rule_version)]
    if channel:
        items = [o for o in items if o.get("channel") == channel.strip().lower()]
    if reason_code:
        items = [o for o in items if o.get("reason_code") == reason_code]
    return list(reversed(items))


def list_clarity_tickets(
    brand_name: str | None = None,
    rule_id: str | None = None,
    status: str | None = None,
) -> list[dict]:
    items = load_clarity_tickets()
    if brand_name:
        items = [
            t
            for t in items
            if t.get("brand_name", "").strip().lower() == brand_name.strip().lower()
        ]
    if rule_id:
        items = [t for t in items if t.get("rule_id") == rule_id]
    if status:
        items = [t for t in items if t.get("status") == status]
    return list(reversed(items))


def update_clarity_ticket(
    ticket_id: str,
    status: str,
    resolution_note: str,
    actor_id: str,
) -> dict:
    with STORE_LOCK:
        tickets = load_clarity_tickets()
        ticket = next((t for t in tickets if t["ticket_id"] == ticket_id), None)
        if ticket is None:
            raise HTTPException(404, "Clarity ticket not found")
        now_iso = datetime.now(timezone.utc).isoformat()
        ticket.update(
            status=status,
            resolution_note=resolution_note.strip(),
            updated_by=actor_id,
            updated_at=now_iso,
        )
        save_clarity_tickets(tickets)
        log_audit(
            "clarity_ticket_update",
            actor_id,
            ticket_id,
            {
                "rule_id": ticket["rule_id"],
                "rule_version": ticket["rule_version"],
                "status": status,
                "resolution_note": resolution_note.strip(),
            },
        )
        return copy.deepcopy(ticket)
