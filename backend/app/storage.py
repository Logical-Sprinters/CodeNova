"""Transactional database storage, with a legacy JSON adapter for regression tests.

The existing path-based domain interface maps to keyed database collections.
Runtime data is SQL by default; JSON seed files are not the production database.
"""

import copy
import json
import os
import tempfile
from pathlib import Path
from app import config
from app.database import TRANSACTION, read as db_read, write as db_write

from fastapi import HTTPException

STORE_LOCK = TRANSACTION


def read_json(path: Path, default):
    if config.STORAGE_BACKEND == "database":
        return db_read(path.stem, default)
    with STORE_LOCK:
        if not path.exists():
            return copy.deepcopy(default)
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise HTTPException(
                500, f"Cannot read {path.name}; restore a valid JSON backup."
            ) from exc
        if not isinstance(value, type(default)):
            raise HTTPException(500, f"Invalid structure in {path.name}.")
        return value


def write_json(path: Path, value):
    if config.STORAGE_BACKEND == "database":
        db_write(path.stem, value)
        return
    with STORE_LOCK:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=path.parent,
                prefix=f".{path.stem}-",
                suffix=".tmp",
                delete=False,
            ) as file:
                temporary = Path(file.name)
                json.dump(value, file, ensure_ascii=False, indent=2)
                file.write("\n")
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
