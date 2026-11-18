from collections import defaultdict, deque
from threading import Lock
import time
from urllib.parse import quote

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app import config
from app.auth import get_user
from app import auth_service as service

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])
_attempts = defaultdict(deque)
_attempt_lock = Lock()


class Credentials(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class Signup(Credentials):
    name: str = Field(min_length=2, max_length=80)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value):
        if len(value.strip()) < 2:
            raise ValueError("Name must contain at least two characters")
        return value.strip()


class Refresh(BaseModel):
    refresh_token: str = Field(min_length=10, max_length=4096)


class PasswordChange(BaseModel):
    model_config = ConfigDict(extra="forbid")
    password: str = Field(min_length=8, max_length=128)
    current_password: str | None = Field(default=None, max_length=128)


class Recover(BaseModel):
    email: str = Field(min_length=3, max_length=254)


class ProfileUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=2, max_length=80)

    @field_validator("name")
    @classmethod
    def clean_display_name(cls, value):
        if len(value.strip()) < 2:
            raise ValueError("Display name must contain at least two characters")
        return value.strip()


class PreferencesUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email_updates: bool | None = None
    review_activity: bool | None = None
    product_news: bool | None = None


def limit(request, email):
    key = (request.client.host if request.client else "local", email.strip().lower())
    now = time.monotonic()
    with _attempt_lock:
        recent = _attempts[key]
        while recent and recent[0] < now - 60:
            recent.popleft()
        if len(recent) >= 10:
            raise HTTPException(429, "Too many attempts. Wait one minute and retry.")
        recent.append(now)


@router.post("/login")
def login(body: Credentials, request: Request):
    limit(request, body.email)
    return service.login(body.email, body.password)


@router.post("/signup")
def signup(body: Signup, request: Request):
    limit(request, body.email)
    if len(body.password) < 8:
        raise HTTPException(422, "Use a password with at least eight characters")
    if config.AUTH_PROVIDER == "supabase":
        return service.provider_session(
            service.supabase_request(
                "POST",
                "signup",
                {
                    "email": body.email.strip().lower(),
                    "password": body.password,
                    "data": {"name": body.name.strip()},
                },
            )
        )
    # Public registration can never choose or elevate its role.
    return service.issue_tokens(
        service.create_local_user(body.email, body.password, body.name, role="creator")
    )


@router.post("/refresh")
def refresh(body: Refresh):
    return service.refresh_session(body.refresh_token)


@router.get("/me")
def me(user=Depends(get_user)):
    return {"user": service.public_user(user), "auth_provider": config.AUTH_PROVIDER}


@router.patch("/profile")
def update_profile(
    body: ProfileUpdate,
    user=Depends(get_user),
    authorization: str | None = Header(default=None),
):
    token = (
        authorization.split(" ", 1)[1].strip()
        if authorization and authorization.lower().startswith("bearer ")
        else None
    )
    updated = service.update_display_name(user, body.name, token=token)
    return {"user": updated, "message": "Display name updated"}


@router.get("/preferences")
def read_preferences(user=Depends(get_user)):
    return service.get_preferences(user["user_id"])


@router.put("/preferences")
def write_preferences(body: PreferencesUpdate, user=Depends(get_user)):
    payload = {k: v for k, v in body.model_dump().items() if v is not None}
    return service.save_preferences(user["user_id"], payload)


@router.post("/logout")
def logout(user=Depends(get_user), authorization: str = Header()):
    service.logout(authorization.split(" ", 1)[1])
    return {"message": "Signed out"}


@router.post("/recover")
def recover(body: Recover, request: Request):
    limit(request, body.email)
    if config.AUTH_PROVIDER != "supabase":
        raise HTTPException(
            503,
            "Email password reset requires configured Supabase Auth/email delivery. Local mode does not pretend to send email.",
        )
    if not config.AUTH_REDIRECT_URL.startswith(
        ("https://", "http://localhost:", "http://127.0.0.1:")
    ):
        raise HTTPException(
            503,
            "Configure AUTH_REDIRECT_URL and its Supabase redirect allowlist before sending recovery email",
        )
    service.supabase_request(
        "POST",
        "recover?redirect_to=" + quote(config.AUTH_REDIRECT_URL, safe=""),
        {"email": body.email.strip().lower()},
    )
    return {
        "message": "If the account exists, the provider will send reset instructions."
    }


@router.get("/config")
def public_config():
    return {
        "auth_provider": config.AUTH_PROVIDER,
        "demo_accounts_enabled": config.AUTH_PROVIDER == "local"
        and config.SEED_DEMO_USERS,
        "email_reset_available": config.AUTH_PROVIDER == "supabase",
    }


@router.put("/password")
def change_password(
    body: PasswordChange, user=Depends(get_user), authorization: str = Header()
):
    token = authorization.split(" ", 1)[1]
    if config.AUTH_PROVIDER == "supabase":
        service.supabase_request(
            "PUT", "user", {"password": body.password}, token=token
        )
        service.logout(token)
    else:
        with service.STORE_LOCK:
            users = service.load("auth_users")
            current = next((u for u in users if u["user_id"] == user["user_id"]), None)
            if (
                not current
                or not body.current_password
                or not service.password_matches(
                    body.current_password, current["password_hash"]
                )
            ):
                raise HTTPException(403, "Current password is required and must match")
            current["password_hash"] = service.password_hash(body.password)
            service.save("auth_users", users)
            sessions = service.load("auth_sessions")
            for session in sessions:
                if session["user_id"] == user["user_id"]:
                    session["revoked"] = True
            service.save("auth_sessions", sessions)
    return {"message": "Password updated. Sign in again."}
