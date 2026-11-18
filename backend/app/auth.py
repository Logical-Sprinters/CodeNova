"""Verified bearer tokens; public user-ID headers are never enabled by config."""

from fastapi import Header, HTTPException
from app import config
from app.auth_service import (
    local_user_for_token,
    supabase_profile,
    supabase_request,
    check_provider_revocation,
)
from app.storage import read_json

USERS_FILE = config.DATA_DIR / "users.json"


def get_user(
    authorization: str | None = Header(default=None),
    user_id: str | None = Header(default=None, alias="X-User-Id"),
):
    if config.ALLOW_LEGACY_DEMO_HEADERS and user_id:
        user = next(
            (u for u in read_json(USERS_FILE, []) if u.get("user_id") == user_id), None
        )
        if user and user.get("role") in {"creator", "reviewer", "admin"}:
            return user
        raise HTTPException(401, "Invalid user")
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Sign in to obtain an access token")
    token = authorization.split(" ", 1)[1].strip()
    if config.AUTH_PROVIDER == "supabase":
        check_provider_revocation(token)
        return supabase_profile(supabase_request("GET", "user", token=token))
    return local_user_for_token(token)


def can_read(record, user):
    return (
        user.get("role") in {"reviewer", "admin"}
        or record.get("creator_id") == user["user_id"]
    )


def require_read_access(record, user):
    if not can_read(record, user):
        raise HTTPException(403, "You do not have access to this submission")


def require_reviewer(user):
    if user.get("role") not in {"reviewer", "admin"}:
        raise HTTPException(403, "Only reviewers can manage the shared brand library")
