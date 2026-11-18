"""Evaluation access is limited by trusted metadata, never client-controlled data."""

import time

import pytest
from fastapi import HTTPException

from app.auth_service import supabase_profile


def remote(metadata=None, user_metadata=None):
    return {
        "id": "expiry-test-user",
        "email": "test@example.com",
        "app_metadata": metadata or {},
        "user_metadata": user_metadata or {},
    }


def test_normal_accounts_do_not_require_expiry():
    assert supabase_profile(remote())["role"] == "creator"


def test_active_evaluation_reviewer():
    assert (
        supabase_profile(
            remote(
                {
                    "brandguard_role": "reviewer",
                    "brandguard_access_until": int(time.time()) + 600,
                }
            )
        )["role"]
        == "reviewer"
    )


@pytest.mark.parametrize("expiry", [0, 1, -1, "999999999999", None, True, 1.5])
def test_expired_or_malformed_evaluation_access_is_denied(expiry):
    with pytest.raises(HTTPException) as error:
        supabase_profile(remote({"brandguard_access_until": expiry}))
    assert error.value.status_code == 403


def test_editable_metadata_cannot_extend_expired_access():
    with pytest.raises(HTTPException):
        supabase_profile(
            remote(
                {"brandguard_access_until": 1},
                {"brandguard_access_until": int(time.time()) + 999999},
            )
        )


def test_editable_metadata_cannot_expire_an_ordinary_user():
    assert (
        supabase_profile(remote(user_metadata={"brandguard_access_until": 1}))["role"]
        == "creator"
    )
