"""Local password/token auth or Supabase Auth, selected explicitly by config."""

import hashlib
import hmac
import os
import re
import secrets
import time
from uuid import uuid4

import httpx
import jwt
from fastapi import HTTPException

from app import config
from app.storage import STORE_LOCK, read_json, write_json


def load(collection):
    return read_json(config.DATA_DIR / f"{collection}.json", [])


def save(collection, values):
    write_json(config.DATA_DIR / f"{collection}.json", values)


def public_user(user):
    return {key: user.get(key) for key in ("user_id", "email", "name", "role")}


def password_hash(password):
    salt = secrets.token_hex(16)
    rounds = 600_000
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode(), salt.encode(), rounds
    ).hex()
    return f"pbkdf2_sha256${rounds}${salt}${digest}"


def password_matches(password, stored):
    try:
        algorithm, rounds, salt, expected = stored.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        actual = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), salt.encode(), int(rounds)
        ).hex()
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def secret():
    if config.JWT_SECRET:
        if len(config.JWT_SECRET) < 32:
            raise HTTPException(500, "JWT_SECRET must be at least 32 characters")
        return config.JWT_SECRET
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = config.DATA_DIR / ".jwt_secret"
    if not path.exists():
        try:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as file:
                file.write(secrets.token_urlsafe(48))
        except FileExistsError:
            pass
    return path.read_text().strip()


def create_local_user(email, password, name, role="creator", user_id=None):
    email = email.strip().lower()
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise HTTPException(422, "Enter a valid email address")
    if role not in {"creator", "reviewer", "admin"}:
        raise HTTPException(422, "Invalid role")
    if len(name.strip()) < 2:
        raise HTTPException(422, "Name must contain at least two characters")
    if len(password) < 8 or len(password) > 128:
        raise HTTPException(422, "Password must be 8–128 characters")
    with STORE_LOCK:
        users = load("auth_users")
        if any(user["email"] == email for user in users):
            raise HTTPException(409, "An account with this email already exists")
        user = {
            "user_id": user_id or str(uuid4()),
            "email": email,
            "name": name.strip()[:80],
            "role": role,
            "password_hash": password_hash(password),
        }
        users.append(user)
        save("auth_users", users)
        profiles = [p for p in load("users") if p["user_id"] != user["user_id"]]
        profiles.append(public_user(user))
        save("users", profiles)
        return public_user(user)


def seed_demo_accounts():
    existing = {user["email"] for user in load("auth_users")}
    for email, name, role, uid in (
        ("creator@brandguard.demo", "Alice", "creator", "u1"),
        ("reviewer@brandguard.demo", "Bob", "reviewer", "u2"),
    ):
        if email not in existing:
            create_local_user(email, "Demo@12345", name, role, uid)


def issue_tokens(user):
    with STORE_LOCK:
        now = int(time.time())
        refresh = secrets.token_urlsafe(48)
        sid = str(uuid4())
        sessions = load("auth_sessions")
        sessions.append(
            {
                "id": sid,
                "user_id": user["user_id"],
                "refresh_hash": hashlib.sha256(refresh.encode()).hexdigest(),
                "expires_at": now + 7 * 86400,
                "revoked": False,
            }
        )
        # Bound dead session accumulation during local demos.
        save("auth_sessions", [s for s in sessions if s["expires_at"] > now])
        access = jwt.encode(
            {
                "sub": user["user_id"],
                "sid": sid,
                "jti": str(uuid4()),
                "iat": now,
                "exp": now + 1800,
                "iss": "brandguard-backend",
                "aud": "brandguard-mobile",
            },
            secret(),
            algorithm="HS256",
        )
        return {
            "access_token": access,
            "refresh_token": refresh,
            "expires_in": 1800,
            "token_type": "bearer",
            "user": public_user(user),
            "auth_provider": "local",
        }


def local_claims(token):
    try:
        return jwt.decode(
            token,
            secret(),
            algorithms=["HS256"],
            audience="brandguard-mobile",
            issuer="brandguard-backend",
            options={"require": ["sub", "sid", "exp", "iat", "iss", "aud", "jti"]},
        )
    except jwt.PyJWTError as error:
        raise HTTPException(401, "Invalid or expired access token") from error


def local_user_for_token(token):
    claims = local_claims(token)
    with STORE_LOCK:
        session = next(
            (s for s in load("auth_sessions") if s["id"] == claims["sid"]), None
        )
        if (
            not session
            or session["revoked"]
            or session["expires_at"] <= time.time()
            or session["user_id"] != claims["sub"]
        ):
            raise HTTPException(401, "Session expired or revoked")
        user = next(
            (u for u in load("auth_users") if u["user_id"] == claims["sub"]), None
        )
        if user is None:
            raise HTTPException(401, "User no longer exists")
        return public_user(user)


def supabase_request(method, path, body=None, token=None, admin=False):
    key = config.SUPABASE_SERVICE_ROLE_KEY if admin else config.SUPABASE_PUBLISHABLE_KEY
    if not key or not config.SUPABASE_URL:
        raise HTTPException(503, "Supabase is not configured")
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token or (admin and key.count(".") == 2):
        headers["Authorization"] = f"Bearer {token or key}"
    try:
        response = httpx.request(
            method,
            f"{config.SUPABASE_URL}/auth/v1/{path}",
            headers=headers,
            json=body,
            timeout=15,
        )
    except httpx.HTTPError as error:
        raise HTTPException(503, "Authentication provider is unreachable") from error
    if response.is_error:
        try:
            data = response.json()
            message = (
                data.get("msg")
                or data.get("error_description")
                or data.get("message")
                or "Authentication failed"
            )
        except ValueError:
            message = "Authentication failed"
        raise HTTPException(
            401 if response.status_code in (400, 401, 403) else 503, str(message)[:240]
        )
    return response.json() if response.content else {}


def provider_token_keys(token):
    keys = ["token:" + hashlib.sha256(token.encode()).hexdigest()]
    try:
        claims = jwt.decode(token, options={"verify_signature": False})
        sid = claims.get("session_id")
        if isinstance(sid, str) and len(sid) < 100:
            keys.append("session:" + sid)
    except jwt.PyJWTError:
        pass
    return keys


def check_provider_revocation(token):
    keys = set(provider_token_keys(token))
    if any(row["id"] in keys for row in load("provider_revocations")):
        raise HTTPException(401, "Session signed out through this backend")


def revoke_provider_token(token):
    with STORE_LOCK:
        rows = load("provider_revocations")
        existing = {r["id"] for r in rows}
        rows.extend(
            {"id": key, "revoked_at": int(time.time())}
            for key in provider_token_keys(token)
            if key not in existing
        )
        save("provider_revocations", rows)


def supabase_profile(remote):
    uid = remote.get("id")
    if not uid:
        raise HTTPException(401, "Provider returned no user identity")
    # Only trusted app_metadata may grant a role or extend evaluation access.
    metadata = remote.get("app_metadata") or {}
    if "brandguard_access_until" in metadata:
        expires = metadata["brandguard_access_until"]
        if (
            type(expires) is not int
            or not 0 <= expires <= 999999999999
            or expires <= time.time()
        ):
            raise HTTPException(403, "Temporary demo access has expired")
    role = metadata.get("brandguard_role", "creator")
    if role not in {"creator", "reviewer", "admin"}:
        role = "creator"
    user = {
        "user_id": uid,
        "email": remote.get("email"),
        "role": role,
        "name": str(
            remote.get("user_metadata", {}).get("name") or remote.get("email") or "User"
        )[:80],
    }
    with STORE_LOCK:
        profiles = [u for u in load("users") if u["user_id"] != uid]
        profiles.append(user)
        save("users", profiles)
    return user


def provider_session(data):
    if not data.get("access_token"):
        return {
            "requires_confirmation": True,
            "message": "Check your email to confirm your account before signing in.",
        }
    user = supabase_profile(
        data.get("user") or supabase_request("GET", "user", token=data["access_token"])
    )
    return {
        key: data.get(key)
        for key in ("access_token", "refresh_token", "expires_in", "token_type")
    } | {"user": user, "auth_provider": "supabase"}


def login(email, password):
    if config.AUTH_PROVIDER == "supabase":
        return provider_session(
            supabase_request(
                "POST",
                "token?grant_type=password",
                {"email": email.strip().lower(), "password": password},
            )
        )
    with STORE_LOCK:
        user = next(
            (u for u in load("auth_users") if u["email"] == email.strip().lower()), None
        )
        if not user or not password_matches(password, user["password_hash"]):
            raise HTTPException(401, "Incorrect email or password")
        return issue_tokens(user)


def refresh_session(refresh):
    if config.AUTH_PROVIDER == "supabase":
        return provider_session(
            supabase_request(
                "POST", "token?grant_type=refresh_token", {"refresh_token": refresh}
            )
        )
    digest = hashlib.sha256(refresh.encode()).hexdigest()
    with STORE_LOCK:
        sessions = load("auth_sessions")
        session = next(
            (s for s in sessions if hmac.compare_digest(s["refresh_hash"], digest)),
            None,
        )
        if not session or session["revoked"] or session["expires_at"] <= time.time():
            raise HTTPException(401, "Invalid or expired refresh token")
        user = next(
            (u for u in load("auth_users") if u["user_id"] == session["user_id"]), None
        )
        if user is None:
            raise HTTPException(401, "User no longer exists")
        session["revoked"] = True
        save("auth_sessions", sessions)
        return issue_tokens(user)


def logout(token):
    if config.AUTH_PROVIDER == "supabase":
        # Backend denial is durable even if the remote logout request fails.
        revoke_provider_token(token)
        supabase_request("POST", "logout?scope=local", token=token)
    else:
        claims = local_claims(token)
        with STORE_LOCK:
            sessions = load("auth_sessions")
            for session in sessions:
                if session["id"] == claims["sid"]:
                    session["revoked"] = True
            save("auth_sessions", sessions)
