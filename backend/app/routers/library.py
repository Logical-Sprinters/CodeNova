"""Shared, reviewer-managed brand rules, descriptive guidelines and trusted facts."""

import copy
from datetime import datetime, timezone
from typing import Literal
from uuid import uuid4
from urllib.parse import urlparse

import regex
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field, field_validator

from app import config
from app.auth import get_user, require_reviewer
from app.audit.store import log_audit
from app.checks.llm.verifier import active_facts_for_brand
from app.checks.visual.inspector import compute_logo_signature
from app.rules_store.store import (
    EPOCH_START,
    load_rule_store,
    normalize_rule,
    parse_timestamp,
    resolve_active_rules,
)
from app.rules_store import store as rule_store
from app.schemas.brand import parse_optional_timestamp
from app.storage import STORE_LOCK, read_json, write_json

router = APIRouter(prefix="/api/v1/library", tags=["Brand library"])


def _bump_semver(version: str) -> str:
    parts = str(version or "1.0.0").split(".")
    if len(parts) == 3 and all(p.isdigit() for p in parts):
        return f"{parts[0]}.{parts[1]}.{int(parts[2]) + 1}"
    return f"{version}.1"


class LibraryItem(BaseModel):
    rule_id: str | None = Field(default=None, max_length=64)
    title: str = Field(min_length=1, max_length=160)
    brand_name: str = Field(default="Acme", min_length=1, max_length=128)
    category: str = Field(default="Product Claims", max_length=80)
    description: str = Field(default="", max_length=50000)
    rule_text: str = Field(default="", max_length=50000)
    rule_quote: str | None = Field(default=None, max_length=2000)
    content: str = Field(default="", max_length=100000)
    source_url: str = Field(default="", max_length=2048)
    pattern: str = Field(default="", max_length=500)
    severity: Literal["warning", "review", "critical"] = "review"
    suggestion: str = Field(default="", max_length=2000)
    replacement: str | None = Field(default=None, max_length=2000)
    enabled: bool = True
    verified: bool = False
    version: str | None = Field(default=None, max_length=32)
    effective_from: str | None = Field(default=None, max_length=64)
    expires_at: str | None = Field(default=None, max_length=64)
    supersedes: str | None = Field(default=None, max_length=128)
    topic_key: str | None = Field(default=None, max_length=128)
    canonical_value: str | None = Field(default=None, max_length=256)
    topic_keywords: list[str] = Field(default_factory=list, max_length=30)
    channels: list[str] = Field(default_factory=lambda: ["all"], max_length=20)
    owner_id: str | None = Field(default=None, max_length=128)
    rule_type: Literal["regex", "visual_palette", "visual_logo", "fact_claim"] = "regex"
    allowed_hex_colors: list[str] = Field(default_factory=list, max_length=30)
    banned_hex_colors: list[str] = Field(default_factory=list, max_length=30)
    deprecated_logo_hashes: list[str | dict] = Field(default_factory=list, max_length=30)

    @field_validator("title", "brand_name")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("Value must not be blank")
        return value.strip()

    @field_validator("source_url")
    @classmethod
    def source(cls, value):
        if value and (
            urlparse(value).scheme not in {"http", "https"}
            or not urlparse(value).netloc
        ):
            raise ValueError(
                "Source URL must be http(s), or empty for an uploaded/manual source"
            )
        return value

    @field_validator("effective_from", "expires_at")
    @classmethod
    def valid_dates(cls, value):
        return parse_optional_timestamp(value)


def collection(kind):
    if kind not in {"guidelines", "facts", "rules"}:
        raise HTTPException(404, "Unknown library")
    return config.DATA_DIR / f"library_{kind}.json"


def rule_rows(brand_name, as_of: str | None = None, channel: str = "all"):
    store = load_rule_store()
    brand = store["brands"].get(brand_name.strip().lower())
    if not brand:
        return []
    version = brand["current_version"]
    if as_of is not None or (channel and channel != "all"):
        active, _ = resolve_active_rules(brand_name, check_at=as_of, channel=channel)
        brand_ids = {r.get("id") for r in brand["versions"][version]["rules"]}
        rows_source = [r for r in active if r.get("id") in brand_ids]
    else:
        rows_source = [
            normalize_rule(r, version) for r in brand["versions"][version]["rules"]
        ]
    return [
        {
            "id": r["id"],
            "title": r.get("name", r["id"]),
            "brand_name": brand_name,
            "pattern": r.get("pattern", ""),
            "description": r.get("message", ""),
            "rule_text": r.get("rule_text", ""),
            "rule_quote": r.get("rule_quote", ""),
            "version": r.get("version", "1.0.0"),
            "severity": r.get("severity", "review"),
            "suggestion": r.get("suggestion", ""),
            "replacement": r.get("replacement"),
            "enabled": r.get("enabled", True),
            "effective_from": r.get("effective_from"),
            "expires_at": r.get("expires_at"),
            "supersedes": r.get("supersedes"),
            "topic_key": r.get("topic_key"),
            "canonical_value": r.get("canonical_value"),
            "topic_keywords": r.get("topic_keywords", []),
            "channels": r.get("channels", ["all"]),
            "owner_id": r.get("owner_id", "u2"),
            "rule_type": r.get("rule_type", "regex"),
            "allowed_hex_colors": r.get("allowed_hex_colors", []),
            "banned_hex_colors": r.get("banned_hex_colors", []),
            "deprecated_logo_hashes": r.get("deprecated_logo_hashes", []),
        }
        for r in rows_source
    ]


def _validate_window(eff: str | None, exp: str | None):
    if eff and exp:
        if parse_timestamp(exp) <= parse_timestamp(eff):
            raise HTTPException(422, "expires_at must be strictly after effective_from")


def update_rule(brand_name, item_id, value: LibraryItem | None, actor_id: str = "u2"):
    store = load_rule_store()
    brand_key = brand_name.strip().lower()
    brand = store["brands"].setdefault(
        brand_key, {"current_version": "", "versions": {}}
    )
    old = brand["versions"].get(brand["current_version"], {"rules": []})
    rules = copy.deepcopy(old["rules"])
    existing_rule = next((r for r in rules if r["id"] == item_id), None)
    if value is None and existing_rule is None:
        raise HTTPException(404, "Rule not found")
    rules = [r for r in rules if r["id"] != item_id]
    if value is not None:
        if value.rule_type == "regex":
            if not value.pattern.strip():
                raise HTTPException(
                    422, "A regex pattern is required for an enforceable rule"
                )
            try:
                regex.compile(value.pattern)
            except regex.error as error:
                raise HTTPException(422, f"Invalid regex pattern: {error}") from error
        rule_text = (
            value.rule_text.strip()
            or value.description.strip()
            or value.title.strip()
        )
        if value.rule_quote and value.rule_quote not in rule_text:
            raise HTTPException(
                422, "rule_quote must be an exact verbatim substring of rule_text"
            )
        eff = value.effective_from or (
            existing_rule.get("effective_from")
            if existing_rule
            else EPOCH_START
        )
        exp = value.expires_at
        _validate_window(eff, exp)
        if value.version:
            rule_ver = value.version.strip()
        elif existing_rule:
            rule_ver = _bump_semver(existing_rule.get("version", "1.0.0"))
        else:
            rule_ver = "1.0.0"

        channels = [c.strip().lower() for c in value.channels if c.strip()] or ["all"]
        rules.append(
            {
                "id": item_id,
                "name": value.title,
                "version": rule_ver,
                "rule_type": value.rule_type,
                "pattern": value.pattern,
                "severity": value.severity,
                "rule_text": rule_text,
                "rule_quote": value.rule_quote or rule_text[:220],
                "message": value.description or value.title,
                "suggestion": value.suggestion,
                "replacement": value.replacement,
                "enabled": value.enabled,
                "effective_from": eff,
                "expires_at": exp,
                "supersedes": value.supersedes,
                "topic_key": value.topic_key,
                "canonical_value": value.canonical_value,
                "topic_keywords": value.topic_keywords,
                "channels": channels,
                "owner_id": value.owner_id
                or (existing_rule.get("owner_id") if existing_rule else actor_id),
                "allowed_hex_colors": value.allowed_hex_colors,
                "banned_hex_colors": value.banned_hex_colors,
                "deprecated_logo_hashes": value.deprecated_logo_hashes,
            }
        )
    revision = len(brand["versions"])
    version = f"1.0.{revision}"
    while version in brand["versions"]:
        revision += 1
        version = f"1.0.{revision}"
    brand["versions"][version] = {
        "rules": rules,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    brand["current_version"] = version
    write_json(rule_store.RULES_FILE, store)
    return next(
        (r for r in rule_rows(brand_name) if r["id"] == item_id), {"id": item_id}
    )


@router.get("/{kind}")
def list_library(
    kind: str,
    brand_name: str = "Acme",
    as_of: str | None = None,
    channel: str = "all",
    user=Depends(get_user),
):
    with STORE_LOCK:
        path = collection(kind)
        if kind == "rules":
            items = rule_rows(brand_name, as_of=as_of, channel=channel)
        elif kind == "facts" and as_of is not None:
            all_facts = [
                r
                for r in read_json(path, [])
                if r.get("brand_name", "Acme").lower() == brand_name.lower()
            ]
            items = active_facts_for_brand(
                brand_name=brand_name, facts=all_facts, check_at=as_of, channel=channel
            )
        else:
            items = [
                r
                for r in read_json(path, [])
                if r.get("brand_name", "Acme").lower() == brand_name.lower()
            ]
        return {"items": items, "total": len(items)}


@router.post("/{kind}", status_code=201)
def create_item(kind: str, body: LibraryItem, user=Depends(get_user)):
    require_reviewer(user)
    with STORE_LOCK:
        path = collection(kind)
        item_id = (body.rule_id.strip() if (kind == "rules" and body.rule_id and body.rule_id.strip()) else str(uuid4()))
        if kind == "rules":
            if any(r["id"] == item_id for r in rule_rows(body.brand_name)):
                raise HTTPException(409, f"Rule '{item_id}' already exists for this brand")
            result = update_rule(body.brand_name, item_id, body, actor_id=user["user_id"])
        else:
            if kind == "facts" and not body.content.strip():
                raise HTTPException(
                    422, "A factual source needs actual source text, not just a URL"
                )
            now = datetime.now(timezone.utc).isoformat()
            eff = body.effective_from or EPOCH_START
            _validate_window(eff, body.expires_at)
            result = body.model_dump(exclude={"rule_id", "rule_text", "rule_quote"}) | {
                "id": item_id,
                "version": body.version or "1.0.0",
                "effective_from": eff,
                "owner_id": body.owner_id or user["user_id"],
                "creator_id": user["user_id"],
                "created_at": now,
            }
            items = read_json(path, [])
            items.append(result)
            write_json(path, items)
        log_audit(
            "library_create",
            user["user_id"],
            f"library:{kind}",
            {"id": item_id, "brand": body.brand_name},
        )
        return result


@router.put("/{kind}/{item_id}")
def edit_item(kind: str, item_id: str, body: LibraryItem, user=Depends(get_user)):
    require_reviewer(user)
    with STORE_LOCK:
        path = collection(kind)
        if kind == "rules":
            if not any(r["id"] == item_id for r in rule_rows(body.brand_name)):
                raise HTTPException(404, "Rule not found in this brand")
            result = update_rule(body.brand_name, item_id, body, actor_id=user["user_id"])
        else:
            items = read_json(path, [])
            original = next((r for r in items if r["id"] == item_id), None)
            if original is None:
                raise HTTPException(404, "Library item not found")
            if kind == "facts" and not body.content.strip():
                raise HTTPException(422, "Source text is required")
            eff = body.effective_from or original.get("effective_from") or EPOCH_START
            _validate_window(eff, body.expires_at)
            new_ver = body.version or _bump_semver(original.get("version", "1.0.0"))
            result = (
                original
                | body.model_dump(exclude={"rule_id", "rule_text", "rule_quote"})
                | {
                    "version": new_ver,
                    "effective_from": eff,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            write_json(path, [result if r["id"] == item_id else r for r in items])
        log_audit(
            "library_update",
            user["user_id"],
            f"library:{kind}",
            {"id": item_id, "brand": body.brand_name},
        )
        return result


@router.post("/rules/{rule_id}/logo-template")
async def attach_logo_template(
    rule_id: str,
    brand_name: str = "Acme",
    label: str = "Deprecated 2024 Logo",
    file: UploadFile = File(...),
    user=Depends(get_user),
):
    """Upload a deprecated logo image and register its perceptual hash on a visual_logo rule."""
    require_reviewer(user)
    raw = await file.read(5 * 1024 * 1024 + 1)
    if not raw or len(raw) > 5 * 1024 * 1024:
        raise HTTPException(413, "Upload a nonempty image no larger than 5 MB")
    try:
        signature = compute_logo_signature(raw, label=label.strip() or "Deprecated logo")
    except ValueError as error:
        raise HTTPException(422, str(error)) from error

    with STORE_LOCK:
        store = load_rule_store()
        brand_key = brand_name.strip().lower()
        brand = store["brands"].get(brand_key)
        if not brand:
            raise HTTPException(404, "Brand rules not found")
        old = brand["versions"].get(brand["current_version"], {"rules": []})
        rules = copy.deepcopy(old["rules"])
        target = next((r for r in rules if r.get("id") == rule_id), None)
        if target is None:
            raise HTTPException(404, f"Rule '{rule_id}' not found")
        if target.get("rule_type") not in {"visual_logo", None}:
            raise HTTPException(422, f"Rule '{rule_id}' is not a visual_logo rule")
        target["rule_type"] = "visual_logo"
        existing = list(target.get("deprecated_logo_hashes") or [])
        if not any(
            (isinstance(e, dict) and e.get("sha256") == signature["sha256"])
            or (isinstance(e, str) and e == signature["dhash"])
            for e in existing
        ):
            existing.append(signature)
        target["deprecated_logo_hashes"] = existing
        target["version"] = _bump_semver(target.get("version", "1.0.0"))

        revision = len(brand["versions"])
        version = f"1.0.{revision}"
        while version in brand["versions"]:
            revision += 1
            version = f"1.0.{revision}"
        brand["versions"][version] = {
            "rules": rules,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        brand["current_version"] = version
        write_json(rule_store.RULES_FILE, store)
        log_audit(
            "library_logo_template",
            user["user_id"],
            f"library:rules:{rule_id}",
            {
                "rule_id": rule_id,
                "brand": brand_name,
                "label": signature["label"],
                "dhash": signature["dhash"],
                "rules_version": version,
            },
        )
        return {
            "rule_id": rule_id,
            "brand_name": brand_name,
            "rules_version": version,
            "rule_version": target["version"],
            "signature": signature,
            "total_templates": len(existing),
        }


@router.delete("/{kind}/{item_id}")
def delete_item(
    kind: str, item_id: str, brand_name: str = "Acme", user=Depends(get_user)
):
    require_reviewer(user)
    with STORE_LOCK:
        path = collection(kind)
        if kind == "rules":
            update_rule(brand_name, item_id, None, actor_id=user["user_id"])
        else:
            items = read_json(path, [])
            if not any(r["id"] == item_id for r in items):
                raise HTTPException(404, "Library item not found")
            write_json(path, [r for r in items if r["id"] != item_id])
        log_audit("library_delete", user["user_id"], f"library:{kind}", {"id": item_id})
        return {"message": "Deleted"}
