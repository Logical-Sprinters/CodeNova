"""Transactional SQLite/PostgreSQL JSON-entity repository.

Lists are stored as individually keyed database rows, not JSON files. Config
objects use a separate documents table. All nested workflow writes share one
transaction. PostgreSQL uses an advisory transaction lock across workers;
SQLite uses BEGIN IMMEDIATE. This deliberately favors correctness over throughput.
"""

from contextvars import ContextVar
from threading import RLock
import copy

from sqlalchemy import (
    Column,
    Integer,
    JSON,
    MetaData,
    String,
    Table,
    create_engine,
    delete,
    insert,
    select,
    update,
    text,
)

from app import config

metadata = MetaData()
entities = Table(
    "bg_entities",
    metadata,
    Column("collection", String(100), primary_key=True),
    Column("entity_id", String(200), primary_key=True),
    Column("position", Integer, nullable=False),
    Column("payload", JSON, nullable=False),
)
documents = Table(
    "bg_documents",
    metadata,
    Column("name", String(100), primary_key=True),
    Column("payload", JSON, nullable=False),
)
_engines = {}
_guard = RLock()
_current = ContextVar("brandguard_transaction", default=None)
KEYS = {
    "review_records": "check_id",
    "receipts": "receipt_id",
    "audit_log": "audit_id",
    "users": "user_id",
    "auth_users": "user_id",
    "user_preferences": "user_id",
    "finding_overrides": "override_id",
    "clarity_tickets": "ticket_id",
    "conflicts": "conflict_id",
    "approval_seals": "seal_id",
    "library_facts": "id",
    "library_guidelines": "id",
}


def engine():
    url = config.database_url()
    with _guard:
        if url not in _engines:
            config.DATA_DIR.mkdir(parents=True, exist_ok=True)
            options = (
                {"connect_args": {"check_same_thread": False, "timeout": 30}}
                if url.startswith("sqlite:")
                else {"pool_pre_ping": True}
            )
            db = create_engine(url, **options)
            metadata.create_all(db)
            _engines[url] = db
        return _engines[url]


class TransactionLock:
    def __enter__(self):
        _guard.acquire()
        if config.STORAGE_BACKEND == "json":
            return self
        state = _current.get()
        if state is not None:
            state["depth"] += 1
            return self
        try:
            conn = engine().connect()
            if conn.dialect.name == "sqlite":
                conn.exec_driver_sql("BEGIN IMMEDIATE")
            else:
                conn.begin()
                conn.execute(text("SELECT pg_advisory_xact_lock(746328119)"))
            state = {"conn": conn, "depth": 1, "failed": False}
            state["token"] = _current.set(state)
            return self
        except BaseException:
            _guard.release()
            raise

    def __exit__(self, kind, value, traceback):
        try:
            if config.STORAGE_BACKEND == "json":
                return False
            state = _current.get()
            state["failed"] |= kind is not None
            state["depth"] -= 1
            if state["depth"] == 0:
                try:
                    if state["failed"]:
                        state["conn"].rollback()
                    else:
                        state["conn"].commit()
                finally:
                    state["conn"].close()
                    _current.reset(state["token"])
                if state["failed"] and kind is None:
                    raise RuntimeError("Database transaction was rolled back")
        finally:
            _guard.release()
        return False


TRANSACTION = TransactionLock()


def read(name, default):
    with TRANSACTION:
        conn = _current.get()["conn"]
        if isinstance(default, list):
            rows = (
                conn.execute(
                    select(entities.c.payload)
                    .where(entities.c.collection == name)
                    .order_by(entities.c.position)
                )
                .scalars()
                .all()
            )
            return copy.deepcopy(rows)
        value = conn.execute(
            select(documents.c.payload).where(documents.c.name == name)
        ).scalar_one_or_none()
        return copy.deepcopy(default if value is None else value)


def write(name, value):
    with TRANSACTION:
        conn = _current.get()["conn"]
        if isinstance(value, list):
            key = KEYS.get(name, "id")
            rows = []
            for index, item in enumerate(value):
                if not isinstance(item, dict) or key not in item:
                    raise ValueError(f"{name} items require {key}")
                rows.append(
                    {
                        "collection": name,
                        "entity_id": str(item[key]),
                        "position": index,
                        "payload": item,
                    }
                )
            if len({row["entity_id"] for row in rows}) != len(rows):
                raise ValueError(f"Duplicate IDs in {name}")
            conn.execute(delete(entities).where(entities.c.collection == name))
            if rows:
                conn.execute(insert(entities), rows)
        else:
            existing = conn.execute(
                select(documents.c.name).where(documents.c.name == name)
            ).first()
            if existing:
                conn.execute(
                    update(documents)
                    .where(documents.c.name == name)
                    .values(payload=value)
                )
            else:
                conn.execute(insert(documents).values(name=name, payload=value))
