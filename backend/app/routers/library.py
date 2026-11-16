"""Shared, reviewer-managed brand rules, descriptive guidelines and trusted facts."""

import copy
from datetime import datetime, timezone
from typing import Literal
from uuid import uuid4
from urllib.parse import urlparse

import regex
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app import config
from app.auth import get_user, require_reviewer
from app.audit.store import log_audit
from app.rules_store.store import load_rule_store
from app.rules_store import store as rule_store
from app.storage import STORE_LOCK, read_json, write_json

router = APIRouter(prefix="/api/v1/library", tags=["Brand library"])


class LibraryItem(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    brand_name: str = Field(default="Acme", min_length=1, max_length=128)
    category: str = Field(default="Product Claims", max_length=80)
    description: str = Field(default="", max_length=50000)
    content: str = Field(default="", max_length=100000)
    source_url: str = Field(default="", max_length=2048)
    pattern: str = Field(default="", max_length=500)
    severity: Literal["warning", "review", "critical"] = "review"
    suggestion: str = Field(default="", max_length=2000)
    replacement: str | None = Field(default=None, max_length=2000)
    enabled: bool = True
    verified: bool = False

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


def collection(kind):
    if kind not in {"guidelines", "facts", "rules"}:
        raise HTTPException(404, "Unknown library")
    return config.DATA_DIR / f"library_{kind}.json"


def rule_rows(brand_name):
    brand = load_rule_store()["brands"].get(brand_name.strip().lower())
    if not brand:
        return []
    return [
        {
            "id": r["id"],
            "title": r.get("name", r["id"]),
            "brand_name": brand_name,
            "pattern": r["pattern"],
            "description": r.get("message", ""),
            "severity": r.get("severity", "review"),
            "suggestion": r.get("suggestion", ""),
            "replacement": r.get("replacement"),
            "enabled": r.get("enabled", True),
        }
        for r in brand["versions"][brand["current_version"]]["rules"]
    ]


def update_rule(brand_name, item_id, value):
    store = load_rule_store()
    brand_key = brand_name.strip().lower()
    brand = store["brands"].setdefault(
        brand_key, {"current_version": "", "versions": {}}
    )
    old = brand["versions"].get(brand["current_version"], {"rules": []})
    rules = copy.deepcopy(old["rules"])
    if value is None and not any(r["id"] == item_id for r in rules):
        raise HTTPException(404, "Rule not found")
    rules = [r for r in rules if r["id"] != item_id]
    if value is not None:
        if not value.pattern.strip():
            raise HTTPException(
                422, "A regex pattern is required for an enforceable rule"
            )
        try:
            regex.compile(value.pattern)
        except regex.error as error:
            raise HTTPException(422, f"Invalid regex pattern: {error}") from error
        rules.append(
            {
                "id": item_id,
                "name": value.title,
                "pattern": value.pattern,
                "severity": value.severity,
                "message": value.description or value.title,
                "suggestion": value.suggestion,
                "replacement": value.replacement,
                "enabled": value.enabled,
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
def list_library(kind: str, brand_name: str = "Acme", user=Depends(get_user)):
    with STORE_LOCK:
        path = collection(kind)
        items = (
            rule_rows(brand_name)
            if kind == "rules"
            else [
                r
                for r in read_json(path, [])
                if r.get("brand_name", "Acme").lower() == brand_name.lower()
            ]
        )
        return {"items": items, "total": len(items)}


@router.post("/{kind}", status_code=201)
def create_item(kind: str, body: LibraryItem, user=Depends(get_user)):
    require_reviewer(user)
    with STORE_LOCK:
        path = collection(kind)
        item_id = str(uuid4())
        if kind == "rules":
            result = update_rule(body.brand_name, item_id, body)
        else:
            if kind == "facts" and not body.content.strip():
                raise HTTPException(
                    422, "A factual source needs actual source text, not just a URL"
                )
            result = body.model_dump() | {
                "id": item_id,
                "creator_id": user["user_id"],
                "created_at": datetime.now(timezone.utc).isoformat(),
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
            result = update_rule(body.brand_name, item_id, body)
        else:
            items = read_json(path, [])
            original = next((r for r in items if r["id"] == item_id), None)
            if original is None:
                raise HTTPException(404, "Library item not found")
            if kind == "facts" and not body.content.strip():
                raise HTTPException(422, "Source text is required")
            result = (
                original
                | body.model_dump()
                | {"updated_at": datetime.now(timezone.utc).isoformat()}
            )
            write_json(path, [result if r["id"] == item_id else r for r in items])
        log_audit(
            "library_update",
            user["user_id"],
            f"library:{kind}",
            {"id": item_id, "brand": body.brand_name},
        )
        return result


@router.delete("/{kind}/{item_id}")
def delete_item(
    kind: str, item_id: str, brand_name: str = "Acme", user=Depends(get_user)
):
    require_reviewer(user)
    with STORE_LOCK:
        path = collection(kind)
        if kind == "rules":
            update_rule(brand_name, item_id, None)
        else:
            items = read_json(path, [])
            if not any(r["id"] == item_id for r in items):
                raise HTTPException(404, "Library item not found")
            write_json(path, [r for r in items if r["id"] != item_id])
        log_audit("library_delete", user["user_id"], f"library:{kind}", {"id": item_id})
        return {"message": "Deleted"}
