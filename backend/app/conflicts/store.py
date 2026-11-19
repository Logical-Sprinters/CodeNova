import re
from datetime import date, datetime, timezone
from uuid import uuid4

from app import config
from app.storage import STORE_LOCK, read_json, write_json

CONFLICTS_FILE = config.DATA_DIR / "rule_conflicts.json"
FACTS_FILE = config.DATA_DIR / "library_facts.json"

_TOPIC_PHRASES = {
    "transfer_fee": (
        "transfer fee",
        "transfer fees",
        "transaction charge",
        "transaction fee",
        "zero fee",
        "zero-fee",
        "zero fees",
        "no-fee",
        "fee-free",
        "free of charge",
        "free transfer",
        "free transfers",
        "no fee",
    ),
    "pricing": ("price", "pricing", "cost", "plan fee"),
    "returns": ("guaranteed return", "return", "yield"),
    "disclaimer": ("disclaimer", "terms apply"),
}
_ZERO_FEE = re.compile(
    r"(?:\b(?:no|zero|free)\b[\w\s-]{0,30}\b(?:fee|fees|charge|charges|cost)\b"
    r"|\b(?:fee|fees|charge|charges)\b[\w\s-]{0,20}\b(?:zero|free|nil)\b"
    r"|(?:₹|rs\.?|inr)\s*0(?:\.0+)?\b)",
    re.IGNORECASE,
)
_MONEY = re.compile(
    r"(?:₹|rs\.?|inr)\s*(\d+(?:,\d{3})*(?:\.\d+)?)"
    r"|(\d+(?:,\d{3})*(?:\.\d+)?)\s*(?:₹|rs\.?|inr|rupees?)",
    re.IGNORECASE,
)


def _fact_topic(fact: dict) -> str:
    topic = str(fact.get("topic_key") or "").strip().lower()
    if topic:
        return topic
    text = f"{fact.get('title', '')} {fact.get('content', '')}".lower()
    return next(
        (
            key
            for key, phrases in _TOPIC_PHRASES.items()
            if any(phrase in text for phrase in phrases)
        ),
        "",
    )


def _normalized_value(fact: dict) -> str:
    explicit = str(fact.get("normalized_value") or "").strip().casefold()
    text = explicit or str(fact.get("content") or "").strip().casefold()
    if text in {"zero_fee", "no_fee", "free", "nil"}:
        return "0"
    if _ZERO_FEE.search(text):
        return "0"
    match = _MONEY.search(text)
    if match:
        return (match.group(1) or match.group(2)).replace(",", "")
    return " ".join(text.split())[:500]


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _periods_overlap(fact_a: dict, fact_b: dict, on_date: date | None = None) -> bool:
    current_date = on_date or date.today()
    start_a = _parse_date(fact_a.get("effective_from")) or date.min
    end_a = _parse_date(fact_a.get("effective_to")) or date.max
    start_b = _parse_date(fact_b.get("effective_from")) or date.min
    end_b = _parse_date(fact_b.get("effective_to")) or date.max
    return max(start_a, start_b) <= current_date <= min(end_a, end_b)


def _topic_present(topic_key: str, content: str) -> bool:
    text = content.casefold()
    if topic_key == "transfer_fee":
        return any(phrase in text for phrase in _TOPIC_PHRASES[topic_key]) or (
            "transfer" in text and bool(_MONEY.search(text) or _ZERO_FEE.search(text))
        )
    phrases = _TOPIC_PHRASES.get(topic_key, (topic_key.replace("_", " "),))
    return any(phrase in text for phrase in phrases)


def _active_facts(brand_name: str, topic_key: str | None = None) -> list[dict]:
    brand = brand_name.strip().casefold()
    return [
        fact
        for fact in read_json(FACTS_FILE, [])
        if fact.get("brand_name", "Acme").strip().casefold() == brand
        and fact.get("enabled", True)
        and fact.get("verified") is True
        and fact.get("approval_status", "active") == "active"
        and (topic_key is None or _fact_topic(fact) == topic_key)
    ]


def _evidence(fact: dict) -> dict:
    return {
        "fact_id": fact["id"],
        "title": fact.get("title", "Source"),
        "department": fact.get("department", "Not specified"),
        "effective_from": fact.get("effective_from"),
        "effective_to": fact.get("effective_to"),
        "normalized_value": _normalized_value(fact),
        "original_clause": fact.get("content", ""),
        "authority": fact.get("authority", "source"),
    }


def detect_conflicts(
    brand_name: str, content: str, *, persist: bool = True
) -> list[dict]:
    grouped: dict[str, list[dict]] = {}
    for fact in _active_facts(brand_name):
        topic = _fact_topic(fact)
        if topic:
            grouped.setdefault(topic, []).append(fact)

    conflicts = []
    with STORE_LOCK:
        existing = read_json(CONFLICTS_FILE, [])
        for topic, topic_facts in grouped.items():
            if not _topic_present(topic, content):
                continue
            for index, left in enumerate(topic_facts):
                for right in topic_facts[index + 1 :]:
                    if (
                        _normalized_value(left) == _normalized_value(right)
                        or not _periods_overlap(left, right)
                    ):
                        continue
                    fact_ids = sorted((left["id"], right["id"]))
                    current = next(
                        (
                            item
                            for item in existing
                            if item.get("brand_name", "").casefold()
                            == brand_name.strip().casefold()
                            and item.get("topic_key") == topic
                            and sorted(item.get("fact_ids", [])) == fact_ids
                            and item.get("status") == "unresolved"
                        ),
                        None,
                    )
                    if current:
                        conflicts.append(current)
                        continue
                    conflict = {
                        "id": str(uuid4()),
                        "brand_name": brand_name,
                        "topic_key": topic,
                        "status": "unresolved",
                        "detected_at": datetime.now(timezone.utc).isoformat(),
                        "resolved_at": None,
                        "fact_ids": fact_ids,
                        "evidence": [_evidence(left), _evidence(right)],
                    }
                    if persist:
                        existing.append(conflict)
                    conflicts.append(conflict)
        if persist:
            write_json(CONFLICTS_FILE, existing)
    return conflicts


def list_conflicts(
    brand_name: str | None = None, status: str | None = None
) -> list[dict]:
    items = read_json(CONFLICTS_FILE, [])
    if brand_name:
        items = [
            item
            for item in items
            if item.get("brand_name", "").casefold() == brand_name.casefold()
        ]
    if status:
        items = [item for item in items if item.get("status") == status]
    return items


def keep_unresolved(
    conflict_id: str, resolution_reason: str, user_id: str
) -> dict:
    with STORE_LOCK:
        items = read_json(CONFLICTS_FILE, [])
        conflict = next((item for item in items if item.get("id") == conflict_id), None)
        if conflict is None:
            raise LookupError("Conflict not found")
        if conflict.get("status") != "unresolved":
            raise ValueError("This conflict is no longer unresolved")
        conflict["last_reviewed_by"] = user_id
        conflict["last_reviewed_at"] = datetime.now(timezone.utc).isoformat()
        conflict["last_review_reason"] = resolution_reason
        write_json(CONFLICTS_FILE, items)
        return conflict


def resolve_conflict(
    conflict_id: str,
    selected_fact_id: str,
    resolution_reason: str,
    user_id: str,
) -> dict:
    with STORE_LOCK:
        conflicts = read_json(CONFLICTS_FILE, [])
        conflict = next(
            (item for item in conflicts if item.get("id") == conflict_id), None
        )
        if conflict is None:
            raise LookupError("Conflict not found")
        if conflict.get("status") != "unresolved":
            raise ValueError("This conflict is no longer unresolved")
        if selected_fact_id not in set(conflict.get("fact_ids", [])):
            raise ValueError("Selected source is not part of this conflict")

        facts = read_json(FACTS_FILE, [])
        selected = next(
            (fact for fact in facts if fact.get("id") == selected_fact_id), None
        )
        if (
            selected is None
            or selected.get("brand_name", "").casefold()
            != conflict["brand_name"].casefold()
            or not selected.get("enabled", True)
            or selected.get("verified") is not True
            or selected.get("approval_status", "active") != "active"
        ):
            raise ValueError("Selected source is no longer an active verified fact")

        topic = conflict["topic_key"]
        selected_value = _normalized_value(selected)
        affected_fact_ids = set()
        for fact in facts:
            if (
                fact.get("brand_name", "").casefold()
                != conflict["brand_name"].casefold()
                or not fact.get("enabled", True)
                or fact.get("verified") is not True
                or fact.get("approval_status", "active") != "active"
                or _fact_topic(fact) != topic
                or not _periods_overlap(selected, fact)
                or _normalized_value(fact) == selected_value
            ):
                continue
            fact.update(
                approval_status="superseded",
                superseded_by=selected_fact_id,
                superseded_at=datetime.now(timezone.utc).isoformat(),
                superseded_by_user=user_id,
                supersession_reason=resolution_reason,
            )
            affected_fact_ids.add(fact["id"])

        selected.update(
            authority="official",
            authority_selected_at=datetime.now(timezone.utc).isoformat(),
            authority_selected_by=user_id,
            authority_reason=resolution_reason,
        )

        resolved_at = datetime.now(timezone.utc).isoformat()
        resolved_conflict_ids = []
        for item in conflicts:
            item_fact_ids = set(item.get("fact_ids", []))
            if (
                item.get("status") == "unresolved"
                and item.get("brand_name", "").casefold()
                == conflict["brand_name"].casefold()
                and item.get("topic_key") == topic
                and item_fact_ids.intersection(affected_fact_ids)
            ):
                item.update(
                    status="resolved",
                    selected_fact_id=selected_fact_id,
                    resolution_reason=resolution_reason,
                    resolved_by=user_id,
                    resolved_at=resolved_at,
                )
                resolved_conflict_ids.append(item["id"])

        conflict.update(
            status="resolved",
            selected_fact_id=selected_fact_id,
            resolution_reason=resolution_reason,
            resolved_by=user_id,
            resolved_at=resolved_at,
        )
        if conflict_id not in resolved_conflict_ids:
            resolved_conflict_ids.append(conflict_id)

        write_json(FACTS_FILE, facts)
        write_json(CONFLICTS_FILE, conflicts)
        return {
            **conflict,
            "resolved_conflict_ids": resolved_conflict_ids,
            "superseded_fact_ids": sorted(affected_fact_ids),
        }
