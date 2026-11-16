"""Trusted administration only. Passwords are prompted, never command-line args.

Examples (from backend/):
  python manage.py init-db
  python manage.py migrate
  python manage.py create-user --email reviewer@example.com --name Reviewer --role reviewer
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
from app.database import documents, engine, entities, TRANSACTION, _current


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
