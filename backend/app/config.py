"""Server-only configuration. Never put database/AI secrets in Flutter defines."""

import os
import json
from pathlib import Path
from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR = BACKEND_DIR / "data"
load_dotenv(BACKEND_DIR / ".env", override=False)
DATA_DIR = (
    Path(os.environ.get("BRANDGUARD_DATA_DIR", str(DEFAULT_DATA_DIR)))
    .expanduser()
    .resolve()
)
DATABASE_URL = os.environ.get("DATABASE_URL", "")
AUTH_PROVIDER = os.environ.get("AUTH_PROVIDER", "local").strip().lower()
AUTH_REDIRECT_URL = os.environ.get("AUTH_REDIRECT_URL", "")
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_PUBLISHABLE_KEY = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SECRET_KEY", "") or os.environ.get(
    "SUPABASE_SERVICE_ROLE_KEY", ""
)
SUPABASE_STORAGE_BUCKET = os.environ.get("SUPABASE_STORAGE_BUCKET", "brandguard-files")
SEED_DEMO_USERS = os.environ.get("SEED_DEMO_USERS", "true").lower() == "true"
JWT_SECRET = os.environ.get("JWT_SECRET", "")
AI_PROVIDER = os.environ.get("AI_PROVIDER", "disabled").lower()
AI_API_KEY = os.environ.get("AI_API_KEY", "") or (
    os.environ.get("OPENROUTER_API_KEY", "") if AI_PROVIDER == "openrouter" else ""
)
AI_BASE_URL = os.environ.get(
    "AI_BASE_URL",
    (
        "https://openrouter.ai/api/v1"
        if AI_PROVIDER == "openrouter"
        else "https://api.openai.com/v1"
    ),
).rstrip("/")
AI_MODEL = os.environ.get(
    "AI_MODEL", "openai/gpt-5.4-mini" if AI_PROVIDER == "openrouter" else "gpt-5.4-mini"
)
TESSERACT_CMD = os.environ.get("TESSERACT_CMD", "").strip()
PUBLIC_APP_URL = os.environ.get("PUBLIC_APP_URL", os.environ.get("APP_URL", "")).rstrip(
    "/"
)
SUPABASE_EMAIL_HOOK_SECRET = os.environ.get("SUPABASE_EMAIL_HOOK_SECRET", "")
RESEND_API_KEY = os.environ.get("RESEND_API_KEY", "")
RESEND_API_URL = os.environ.get("RESEND_API_URL", "").rstrip("/")
EMAIL_FROM = os.environ.get("EMAIL_FROM", "")
CORS_ORIGINS = [
    s.strip() for s in os.environ.get("CORS_ORIGINS", "").split(",") if s.strip()
]
# Compatibility tests only. There is intentionally no environment flag enabling ID-header login.
STORAGE_BACKEND = "database"
ALLOW_LEGACY_DEMO_HEADERS = False


def database_url():
    url = DATABASE_URL or f'sqlite:///{DATA_DIR / "brandguard.sqlite3"}'
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg://", 1)
    elif url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


def initialize_data_store():
    from app.storage import STORE_LOCK, read_json, write_json

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if AUTH_PROVIDER not in {"local", "supabase"}:
        raise RuntimeError("AUTH_PROVIDER must be local or supabase")
    if AUTH_PROVIDER == "supabase" and (
        not SUPABASE_URL.startswith("https://")
        or not SUPABASE_PUBLISHABLE_KEY
        or not DATABASE_URL.startswith(
            ("postgres://", "postgresql://", "postgresql+psycopg://")
        )
    ):
        raise RuntimeError(
            "Supabase mode requires HTTPS SUPABASE_URL, publishable key and PostgreSQL DATABASE_URL. See .env.example."
        )
    with STORE_LOCK:
        for name in (
            "users.json",
            "brand_rules.json",
            "review_records.json",
            "receipts.json",
            "audit_log.json",
            "rule_conflicts.json",
        ):
            default = {} if name == "brand_rules.json" else []
            marker = DATA_DIR / name
            if name in ("users.json", "brand_rules.json"):
                seed = json.loads((DEFAULT_DATA_DIR / name).read_text(encoding="utf-8"))
                current = read_json(marker, default)
                if not current:
                    write_json(
                        marker,
                        (seed if name != "users.json" else []),
                    )
        if (
            STORAGE_BACKEND == "database"
            and AUTH_PROVIDER == "local"
            and SEED_DEMO_USERS
        ):
            from app.auth_service import seed_demo_accounts

            seed_demo_accounts()
