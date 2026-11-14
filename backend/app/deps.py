"""Who is asking, and in what capacity.

This build has no authentication: the caller names themselves with an X-User-Id
header and the server reads their role from the users table. That is deliberately
weak, and it is stated as a limitation rather than dressed up as SSO.
What it does guarantee: the client cannot grant itself a permission, because every
role check happens server-side and the database re-checks it again.
"""
from fastapi import Depends, Header, HTTPException

from .db import fetch_one

APPROVER_ROLES = {"reviewer", "admin"}


def current_user(x_user_id: str = Header(default="")) -> dict:
    if not x_user_id:
        raise HTTPException(status_code=401, detail="X-User-Id header is required")
    user = fetch_one(
        "SELECT user_id, display_name, email, role, is_active FROM users WHERE user_id = %s",
        (x_user_id,),
    )
    if not user:
        raise HTTPException(status_code=401, detail="unknown user")
    if not user["is_active"]:
        raise HTTPException(status_code=403, detail="this account is deactivated")
    return user


def current_reviewer(user: dict = Depends(current_user)) -> dict:
    if user["role"] not in APPROVER_ROLES:
        raise HTTPException(status_code=403, detail="approval requires a reviewer")
    return user
