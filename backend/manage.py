"""Trusted administration only. Passwords and AI keys are prompted, never command-line args.

Examples (from backend/):
  python manage.py init-db
  python manage.py migrate
  python manage.py create-user --email reviewer@example.com --name Reviewer --role reviewer
  python manage.py configure-ai
  python manage.py test-ai
  python manage.py backup --output /private/path/backup.json
  python manage.py restore --input /private/path/backup.json --confirm-overwrite
"""

import argparse
from datetime import datetime, timezone
from getpass import getpass
import json
import os
from pathlib import Path

from sqlalchemy import delete, insert, select

from app import auth_service, config
from app.checks.llm.verifier import run_ai_verification
from app.database import documents, engine, entities, TRANSACTION, _current


_AI_PROVIDER_DEFAULTS = {
    "gemini": (
        "https://generativelanguage.googleapis.com/v1beta/openai",
        "gemini-3.5-flash-lite",
    ),
    "openrouter": (
        "https://openrouter.ai/api/v1",
        "nvidia/nemotron-3-super-120b-a12b:free",
    ),
    "openai": (
        "https://api.openai.com/v1",
        "gpt-5.4-mini",
    ),
}


def _upsert_env_file(env_path: Path, updates: dict[str, str], example_path: Path | None = None) -> None:
    if env_path.exists():
        lines = env_path.read_text(encoding="utf-8").splitlines()
    elif example_path and example_path.exists():
        lines = example_path.read_text(encoding="utf-8").splitlines()
    else:
        lines = []

    seen = set()
    updated_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            key = stripped.split("=", 1)[0].strip()
            if key in updates:
                updated_lines.append(f"{key}={updates[key]}")
                seen.add(key)
                continue
        updated_lines.append(line)

    for key, value in updates.items():
        if key not in seen:
            updated_lines.append(f"{key}={value}")

    env_path.write_text("\n".join(updated_lines).rstrip() + "\n", encoding="utf-8")
    try:
        os.chmod(env_path, 0o600)
    except OSError:
        pass


def test_ai_live() -> int:
    resolved = config.reload_ai_settings()
    provider = resolved["AI_PROVIDER"]
    if provider == "disabled" or not resolved["AI_API_KEY"]:
        print(
            "AI verification is DISABLED (no AI_API_KEY configured in backend/.env)."
        )
        print("Run `python manage.py configure-ai` (or ENABLE_AI.bat on Windows) to enable it.")
        return 1

    print(
        f"Testing live AI verification via provider='{provider}', model='{resolved['AI_MODEL']}'..."
    )
    probe_fact = {
        "id": "ai-probe-fact",
        "brand_name": "Acme",
        "title": "Acme SLA Reference",
        "content": "Acme Enterprise includes a 99.95% uptime SLA and costs $49 per month.",
        "verified": True,
        "enabled": True,
        "source_url": "https://example.com/sla",
        "version": "1.0.0",
        "channels": ["all"],
    }
    res = run_ai_verification(
        "Acme Enterprise includes a 99.95% uptime SLA and costs $49 per month.",
        brand_facts=[probe_fact],
        brand_name="Acme",
    )
    status = res.get("status", "abstained")
    model = res.get("model") or resolved["AI_MODEL"]
    print(f"Result status: {status} | model: {model}")
    print(f"Message: {res.get('message', '')}")
    if status in {"supported", "needs_review"}:
        print("Live AI verification SUCCEEDED.")
        print("Next: ensure at least 1 Fact Source under Guidelines -> Fact Sources is Verified for real brand checks.")
        return 0
    print("Live AI verification did NOT succeed. Verify your API key, model access, and network connection.")
    return 1


def configure_ai(provider: str | None = None, model: str | None = None, base_url: str | None = None) -> int:
    print("BrandGuard AI Verification Setup")
    print("================================")
    if not provider:
        print("Select AI provider:")
        print("  1) Google Gemini (free Google AI Studio key)")
        print("  2) OpenRouter ($0 ':free' or paid models)")
        print("  3) OpenAI")
        choice = input("Choice [1/2/3, default 1]: ").strip() or "1"
        choice_map = {"1": "gemini", "2": "openrouter", "3": "openai"}
        provider = choice_map.get(choice, choice.lower())
    provider = provider.strip().lower()
    if provider not in _AI_PROVIDER_DEFAULTS:
        raise ValueError("Provider must be one of: gemini, openrouter, openai")

    default_base, default_model = _AI_PROVIDER_DEFAULTS[provider]
    chosen_model = model or (
        input(f"Model [{default_model}]: ").strip() or default_model
    )
    chosen_base = (base_url or default_base).strip().rstrip("/")
    api_key = getpass(f"Paste {provider.upper()} API key (input hidden): ").strip()
    if not api_key or any(ch in api_key for ch in ("\n", "\r")):
        raise ValueError("A single-line API key is required")

    env_path = config.BACKEND_DIR / ".env"
    example_path = config.BACKEND_DIR / ".env.example"
    _upsert_env_file(
        env_path,
        {
            "AI_PROVIDER": provider,
            "AI_API_KEY": api_key,
            "AI_BASE_URL": chosen_base,
            "AI_MODEL": chosen_model,
        },
        example_path=example_path,
    )
    print(f"Saved AI settings to {env_path}.")
    return test_ai_live()


def migrate():
    db = engine()
    if db.dialect.name == "postgresql":
        sql = (Path(__file__).parent / "migrations" / "001_core.sql").read_text()
        # psycopg supports a complete, parameter-free migration script.
        with db.connect() as conn:
            conn.exec_driver_sql(sql)
            conn.commit()
    config.initialize_data_store()
    print("Core schema v1 ready. Supabase storage policies are a separate SQL file.")


def backup(output):
    destination = Path(output).expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with TRANSACTION:
        conn = _current.get()["conn"]
        snapshot = {
            "format": "brandguard-db-v1",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "entities": [
                dict(row) for row in conn.execute(select(entities)).mappings()
            ],
            "documents": [
                dict(row) for row in conn.execute(select(documents)).mappings()
            ],
        }
    # Exclusive create prevents silently overwriting a previous backup.
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as file:
        json.dump(snapshot, file, ensure_ascii=False)
    print(
        "Database backup created. Treat it as SECRET; it contains password hashes/session data."
    )
    print(
        "Back up private object files separately. Keep local JWT_SECRET/.jwt_secret securely too."
    )


def restore(source):
    snapshot = json.loads(Path(source).expanduser().read_text(encoding="utf-8"))
    if snapshot.get("format") != "brandguard-db-v1":
        raise ValueError("Unsupported backup format")
    for key in ("entities", "documents"):
        if not isinstance(snapshot.get(key), list):
            raise ValueError("Invalid backup structure")
    with TRANSACTION:
        conn = _current.get()["conn"]
        conn.execute(delete(entities))
        conn.execute(delete(documents))
        if snapshot["entities"]:
            conn.execute(insert(entities), snapshot["entities"])
        if snapshot["documents"]:
            conn.execute(insert(documents), snapshot["documents"])
    print(
        "Database restored transactionally. Private object files must be restored separately."
    )


def main():
    parser = argparse.ArgumentParser(
        description="BrandGuard trusted server administration"
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init-db")
    commands.add_parser("migrate")
    ai_cfg = commands.add_parser("configure-ai")
    ai_cfg.add_argument("--provider", choices=("gemini", "openrouter", "openai"))
    ai_cfg.add_argument("--model")
    ai_cfg.add_argument("--base-url")
    commands.add_parser("test-ai")
    create = commands.add_parser("create-user")
    create.add_argument("--email", required=True)
    create.add_argument("--name", required=True)
    create.add_argument(
        "--role", choices=("creator", "reviewer", "admin"), default="creator"
    )
    dump = commands.add_parser("backup")
    dump.add_argument("--output", required=True)
    load = commands.add_parser("restore")
    load.add_argument("--input", required=True)
    load.add_argument("--confirm-overwrite", action="store_true", required=True)
    args = parser.parse_args()
    if args.command == "configure-ai":
        raise SystemExit(configure_ai(args.provider, args.model, args.base_url))
    if args.command == "test-ai":
        raise SystemExit(test_ai_live())
    if args.command == "migrate":
        migrate()
        return
    config.initialize_data_store()
    if args.command == "init-db":
        print("Database initialized.")
    elif args.command == "create-user":
        password = getpass("New password (8–128 characters): ")
        if password != getpass("Confirm password: "):
            parser.error("Passwords did not match")
        if len(password) < 8 or len(password) > 128:
            parser.error("Use 8–128 characters")
        if config.AUTH_PROVIDER == "supabase":
            remote = auth_service.supabase_request(
                "POST",
                "admin/users",
                {
                    "email": args.email.strip().lower(),
                    "password": password,
                    "email_confirm": True,
                    "user_metadata": {"name": args.name},
                    "app_metadata": {"brandguard_role": args.role},
                },
                admin=True,
            )
            user = auth_service.supabase_profile(remote)
        else:
            user = auth_service.create_local_user(
                args.email, password, args.name, args.role
            )
        print(json.dumps(user, indent=2))
    elif args.command == "backup":
        backup(args.output)
    elif args.command == "restore":
        restore(args.input)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Do not echo a connection URL or an exception containing credentials.
        print(
            f"Administration failed ({type(error).__name__}). Check configuration, permissions and input."
        )
        raise SystemExit(1)
