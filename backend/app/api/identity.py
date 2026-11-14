from fastapi import APIRouter

from ..db import fetch_all

router = APIRouter(tags=["identity"])


@router.get("/users", summary="Who can sign in, and in what role")
def users():
    return fetch_all(
        """SELECT user_id, display_name, email, role
             FROM users WHERE is_active ORDER BY role, display_name"""
    )
