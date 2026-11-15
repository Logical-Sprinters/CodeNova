import json
from pathlib import Path
from fastapi import Header, HTTPException

# Path to the users JSON file
USERS_FILE = Path(__file__).with_name('users.json')

def get_user(
    user_id: str = Header(None, alias='X-User-Id'),
    role: str = Header(None, alias='X-User-Role')
):
    """FastAPI dependency to retrieve the caller's user dict.

    Raises 401 if missing/invalid. 500 if the user store is missing.
    """
    if not user_id:
        raise HTTPException(status_code=401, detail='Missing X-User-Id header')
    if not USERS_FILE.exists():
        raise HTTPException(status_code=500, detail='User store missing')
    with open(USERS_FILE, 'r', encoding='utf-8') as f:
        users = json.load(f)
    user = next((u for u in users if u['user_id'] == user_id), None)
    if not user:
        raise HTTPException(status_code=401, detail='Invalid user')
    # Optionally override role from header
    if role:
        user['role'] = role
    return user
