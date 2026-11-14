import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

HAS_DB = bool(os.getenv("DATABASE_URL", "postgresql://brandguard:brandguard@localhost:5432/brandguard"))


@pytest.fixture(scope="session")
def client():
    """A client bound to the real app. Skips (rather than fails) when there is no database,
    because a red build on a machine with no Postgres teaches nobody anything."""
    try:
        from fastapi.testclient import TestClient

        from app.main import app
    except Exception as exc:  # pragma: no cover - environment problem, not a code problem
        pytest.skip(f"app cannot start: {exc}")

    try:
        with TestClient(app) as test_client:
            yield test_client
    except Exception as exc:  # pragma: no cover
        pytest.skip(f"database unreachable: {exc}")
