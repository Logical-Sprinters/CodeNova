from datetime import datetime, timezone
import copy
import json

from fastapi import HTTPException

from app import config
from app.config import DATA_DIR, DEFAULT_DATA_DIR
from app.storage import read_json

RULES_FILE = DATA_DIR / "brand_rules.json"
EPOCH_START = "1970-01-01T00:00:00+00:00"


def _load_default_base_rules():
    seed_path = DEFAULT_DATA_DIR / "brand_rules.json"
    if seed_path.is_file():
        data = json.loads(seed_path.read_text(encoding="utf-8"))
        if isinstance(data.get("base_rules"), list):
            return data["base_rules"]
    return [
        {
            "id": "BG-001",
            "name": "Placeholder Token Guard",
            "version": "1.0.0",
            "rule_type": "regex",
            "pattern": r"\blorem ipsum\b|\bTODO\b|\[insert[^\]]*\]",
            "severity": "warning",
            "rule_text": "All published marketing copy must be complete and free of unfinished placeholder tokens such as lorem ipsum, TODO markers, or bracketed insert prompts.",
            "rule_quote": "unfinished placeholder tokens such as lorem ipsum, TODO markers, or bracketed insert prompts",
            "message": "Unfinished placeholder detected.",
            "suggestion": "Replace this placeholder with complete, relevant content.",
            "replacement": "Please insert verified and relevant content here.",
            "effective_from": "2024-01-01T00:00:00+00:00",
            "expires_at": None,
            "supersedes": None,
            "channels": ["all"],
            "owner_id": "u2",
            "enabled": True,
        },
        {
            "id": "BG-002",
            "name": "Absolute Claim Verification",
            "version": "1.0.0",
            "rule_type": "regex",
            "pattern": r"\bguarantee(?:s|d)?(?:\s+\w+){0,3}|\b100%\s*(?:safe|secure|effective)\b|\brisk[- ]free\b",
            "severity": "review",
            "rule_text": "Marketing and product communications must avoid unsupported absolute guarantees such as 100% safe, secure, effective, or risk-free claims unless substantiated by verified evidence.",
            "rule_quote": "avoid unsupported absolute guarantees such as 100% safe, secure, effective, or risk-free claims",
            "message": "Potentially unsupported absolute claim. Verify before publication.",
            "suggestion": "Avoid absolute guarantees unless supported by verifiable evidence.",
            "effective_from": "2024-01-01T00:00:00+00:00",
            "expires_at": None,
            "supersedes": None,
            "channels": ["all"],
            "owner_id": "u2",
            "enabled": True,
        },
    ]


DEFAULT_BASE_RULES = _load_default_base_rules()


def parse_timestamp(value, default=None) -> datetime | None:
    if value is None:
        return default
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc) if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if not isinstance(value, str) or not value.strip():
        return default
    raw = value.strip()
    normalized = raw[:-1] + "+00:00" if raw.endswith(("Z", "z")) else raw
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise HTTPException(422, f"Invalid ISO-8601 timestamp: {value}") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def normalize_rule(raw_rule: dict, default_version: str = "1.0.0") -> dict:
    rule = copy.deepcopy(raw_rule)
    rule_id = str(rule.get("id") or rule.get("rule_id") or "")
    rule["id"] = rule_id
    rule["name"] = str(rule.get("name") or rule_id or "Unnamed rule")
    rule["version"] = str(rule.get("version") or rule.get("rule_version") or default_version)
    rule["rule_type"] = str(rule.get("rule_type") or "regex")
    rule["severity"] = str(rule.get("severity") or "review")
    rule["message"] = str(rule.get("message") or rule["name"])
    rule["rule_text"] = str(
        rule.get("rule_text")
        or rule.get("message")
        or rule.get("suggestion")
        or rule["name"]
    )
    if not rule.get("rule_quote") or rule["rule_quote"] not in rule["rule_text"]:
        rule["rule_quote"] = rule["rule_text"][:220]
    rule["effective_from"] = rule.get("effective_from") or EPOCH_START
    rule["expires_at"] = rule.get("expires_at") or None
    rule["supersedes"] = rule.get("supersedes") or None
    rule["topic_key"] = rule.get("topic_key") or None
    rule["canonical_value"] = rule.get("canonical_value") or None
    rule["topic_keywords"] = list(rule.get("topic_keywords") or [])
    channels = rule.get("channels") or ["all"]
    rule["channels"] = [str(c).strip().lower() for c in channels if str(c).strip()] or ["all"]
    rule["owner_id"] = str(rule.get("owner_id") or "u2")
    rule["enabled"] = bool(rule.get("enabled", True))
    return rule


def load_rule_store():
    if config.STORAGE_BACKEND == "json" and not RULES_FILE.is_file():
        raise HTTPException(500, "Brand rules configuration is missing")
    result = read_json(RULES_FILE, {})
    if not isinstance(result.get("brands"), dict):
        raise HTTPException(500, "Invalid brand rules configuration")
    return result


def get_base_rules(store: dict | None = None) -> list[dict]:
    data = store if store is not None else load_rule_store()
    raw = data.get("base_rules")
    if isinstance(raw, list) and raw:
        return [normalize_rule(r, "1.0.0") for r in raw]
    return [normalize_rule(r, "1.0.0") for r in DEFAULT_BASE_RULES]


def _rule_is_active_in_window(rule: dict, check_dt: datetime, channel: str) -> bool:
    if not rule.get("enabled", True):
        return False
    eff = parse_timestamp(rule.get("effective_from"), parse_timestamp(EPOCH_START))
    exp = parse_timestamp(rule.get("expires_at"), None)
    if eff and check_dt < eff:
        return False
    if exp and check_dt >= exp:
        return False
    channels = rule.get("channels") or ["all"]
    ch = (channel or "all").strip().lower()
    if ch != "all" and "all" not in channels and ch not in channels:
        return False
    return True


def resolve_active_rules(
    brand_name: str,
    check_at: datetime | str | None = None,
    channel: str = "all",
    version_override: str | None = None,
):
    store = load_rule_store()
    check_dt = parse_timestamp(check_at, datetime.now(timezone.utc))
    base_rules = get_base_rules(store)
    brand = store["brands"].get(brand_name.strip().lower())

    brand_version = None
    brand_rules_raw = []
    if brand:
        brand_version = version_override or brand["current_version"]
        if brand_version not in brand.get("versions", {}):
            raise HTTPException(500, "Current brand rules version is missing")
        brand_rules_raw = brand["versions"][brand_version].get("rules", [])

    candidates = base_rules + [
        normalize_rule(r, brand_version or "1.0.0") for r in brand_rules_raw
    ]
    window_active = [r for r in candidates if _rule_is_active_in_window(r, check_dt, channel)]

    # Resolve supersedes links among active rules at check_at.
    superseded_targets = set()
    for rule in window_active:
        target = rule.get("supersedes")
        if target:
            superseded_targets.add(str(target))

    active_rules = []
    for rule in window_active:
        key_with_ver = f"{rule['id']}@{rule['version']}"
        if rule["id"] in superseded_targets or key_with_ver in superseded_targets:
            continue
        active_rules.append(rule)

    meta = {
        "brand_name": brand_name.strip(),
        "rules_version": brand_version,
        "check_at": check_dt.isoformat(),
        "channel": (channel or "all").strip().lower(),
        "active_rule_versions": {r["id"]: r["version"] for r in active_rules},
    }
    return active_rules, meta


def get_brand_rules(brand_name: str, check_at=None, channel: str = "all"):
    store = load_rule_store()
    brand = store["brands"].get(brand_name.strip().lower())
    if not brand:
        return None
    version = brand["current_version"]
    if version not in brand.get("versions", {}):
        raise HTTPException(500, "Current brand rules version is missing")
    rules = [
        normalize_rule(r, version)
        for r in brand["versions"][version].get("rules", [])
    ]
    if check_at is not None or (channel and channel != "all"):
        check_dt = parse_timestamp(check_at, datetime.now(timezone.utc))
        rules = [r for r in rules if _rule_is_active_in_window(r, check_dt, channel)]
    return {"version": version, "rules": rules}


def get_brand_rule_versions(brand_name: str):
    brand = load_rule_store()["brands"].get(brand_name.strip().lower())
    if not brand:
        return None
    return {
        "brand_name": brand_name.strip(),
        "current_version": brand["current_version"],
        "available_versions": list(brand["versions"].keys()),
    }


def diff_rules_snapshot(
    brand_name: str,
    approved_brand_rules_version: str | None,
    approved_rule_versions: dict[str, str] | None = None,
    approved_rules_snapshot: list[dict] | None = None,
    verify_at: datetime | str | None = None,
    channel: str = "all",
):
    store = load_rule_store()
    brand = store["brands"].get(brand_name.strip().lower())
    current_brand_version = brand["current_version"] if brand else None
    check_dt = parse_timestamp(verify_at, datetime.now(timezone.utc))

    if brand and current_brand_version not in brand.get("versions", {}):
        return {
            "changed": True,
            "current_rules_version": current_brand_version,
            "rule_changes": [
                {
                    "rule_id": "*",
                    "name": "Brand Rule Set",
                    "change_type": "version_mismatch",
                    "old_version": approved_brand_rules_version,
                    "new_version": current_brand_version,
                }
            ],
            "summary": (
                f"Brand rules version changed from {approved_brand_rules_version} "
                f"to {current_brand_version}."
            ),
        }

    current_active, _ = resolve_active_rules(brand_name, check_at=check_dt, channel=channel)
    current_by_id = {r["id"]: r for r in current_active}

    # If the check didn't store per-rule versions (legacy record), resolve from its rules_version if present.
    old_versions = dict(approved_rule_versions or {})
    old_names = {r["id"]: r.get("name", r["id"]) for r in (approved_rules_snapshot or [])}
    if not old_versions and approved_brand_rules_version and brand and approved_brand_rules_version in brand.get("versions", {}):
        legacy_rules, _ = resolve_active_rules(
            brand_name, check_at=check_dt, channel=channel, version_override=approved_brand_rules_version
        )
        old_versions = {r["id"]: r["version"] for r in legacy_rules}
        old_names = {r["id"]: r["name"] for r in legacy_rules}

    all_brand_candidates = []
    if brand and current_brand_version in brand.get("versions", {}):
        all_brand_candidates = [
            normalize_rule(r, current_brand_version)
            for r in brand["versions"][current_brand_version].get("rules", [])
        ]
    candidates_by_id = {r["id"]: r for r in (get_base_rules(store) + all_brand_candidates)}
    superseded_by = {}
    for r in current_active:
        if r.get("supersedes"):
            superseded_by[str(r["supersedes"])] = r["id"]

    changes = []
    for rid, old_v in sorted(old_versions.items()):
        cur = current_by_id.get(rid)
        if cur is None:
            cand = candidates_by_id.get(rid)
            change_type = "removed"
            sup_target = superseded_by.get(rid) or superseded_by.get(f"{rid}@{old_v}")
            if sup_target:
                change_type = "superseded"
            elif cand and parse_timestamp(cand.get("expires_at")) and check_dt >= parse_timestamp(cand.get("expires_at")):
                change_type = "expired"
            elif cand and not cand.get("enabled", True):
                change_type = "disabled"
            changes.append(
                {
                    "rule_id": rid,
                    "name": old_names.get(rid) or (cand["name"] if cand else rid),
                    "change_type": change_type,
                    "old_version": old_v,
                    "new_version": None,
                    "superseded_by": sup_target,
                }
            )
        elif str(cur["version"]) != str(old_v):
            changes.append(
                {
                    "rule_id": rid,
                    "name": cur["name"],
                    "change_type": "modified",
                    "old_version": old_v,
                    "new_version": cur["version"],
                }
            )

    for rid, cur in sorted(current_by_id.items()):
        if rid not in old_versions:
            changes.append(
                {
                    "rule_id": rid,
                    "name": cur["name"],
                    "change_type": "added",
                    "old_version": None,
                    "new_version": cur["version"],
                }
            )

    version_changed = approved_brand_rules_version != current_brand_version
    changed = bool(changes) or version_changed
    if not changed:
        summary = "Active brand rules match the approved snapshot."
    elif changes:
        parts = []
        for c in changes:
            if c["change_type"] == "modified":
                parts.append(f"{c['rule_id']} ({c['old_version']} -> {c['new_version']})")
            elif c["change_type"] == "superseded":
                parts.append(f"{c['rule_id']} superseded by {c.get('superseded_by')}")
            elif c["change_type"] == "expired":
                parts.append(f"{c['rule_id']} expired")
            elif c["change_type"] == "added":
                parts.append(f"{c['rule_id']} added (v{c['new_version']})")
            else:
                parts.append(f"{c['rule_id']} {c['change_type']}")
        summary = "Rules changed since approval: " + "; ".join(parts) + "."
    else:
        summary = (
            f"Brand rules version changed from {approved_brand_rules_version} "
            f"to {current_brand_version}."
        )
    return {
        "changed": changed,
        "current_rules_version": current_brand_version,
        "rule_changes": changes,
        "summary": summary,
    }
