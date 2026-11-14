"""One connection pool, dictionary rows, no ORM.

The SQL in database/ is the source of truth and the only part of this project that
can prove its own claims. An ORM would hide it behind a second, weaker model.
"""
from contextlib import contextmanager

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import DATABASE_URL

pool = ConnectionPool(
    DATABASE_URL,
    min_size=1,
    max_size=8,
    open=False,
    # Verify a pooled connection before handing it out. Without this, restarting
    # Postgres (or recreating the schema under a running API) leaves one poisoned
    # connection that turns the next request into a 500.
    check=ConnectionPool.check_connection,
    # No server-side prepared statements. Re-applying database/*.sql while the API
    # is running invalidates cached plans, and a demo should not die because someone
    # reset the schema in another window.
    kwargs={"row_factory": dict_row, "prepare_threshold": None},
)


@contextmanager
def connection():
    with pool.connection() as conn:
        yield conn


def fetch_all(sql: str, params=None) -> list[dict]:
    with pool.connection() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def fetch_one(sql: str, params=None) -> dict | None:
    with pool.connection() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def execute(sql: str, params=None) -> list[dict]:
    """Run one statement, commit, return any RETURNING rows."""
    with pool.connection() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall() if cur.description else []
        conn.commit()
        return rows


def execute_many(statements: list[tuple[str, tuple]]) -> None:
    """Run several statements in one transaction: all of them, or none."""
    with pool.connection() as conn, conn.cursor() as cur:
        for sql, params in statements:
            cur.execute(sql, params)
        conn.commit()
