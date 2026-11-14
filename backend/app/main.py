"""BrandGuard API.

    uvicorn app.main:app --reload --port 8000     # then http://localhost:8000/docs

Seven routers, no ORM, no model calls. Every integrity rule that matters is in the
database; this layer decides what to ask it and how to explain the answer.
"""
import json
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException
from fastapi.responses import JSONResponse
from psycopg.errors import CheckViolation, UniqueViolation

from .api import ROUTERS
from .config import APP_NAME, APP_VERSION
from .db import pool


class SafeJSONResponse(JSONResponse):
    """Serialise anything psycopg hands back (UUID, date, Decimal) instead of
    raising a 500 at the last possible moment. Belt and braces: services cast
    the values they know about; this catches the ones somebody forgets."""

    def render(self, content: Any) -> bytes:
        return json.dumps(content, default=str, separators=(",", ":"),
                          ensure_ascii=False).encode("utf-8")


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool.open()
    pool.wait()
    yield
    pool.close()


app = FastAPI(
    title=APP_NAME,
    version=APP_VERSION,
    lifespan=lifespan,
    default_response_class=SafeJSONResponse,
    description=(
        "Pre-publication brand governance. Findings cite a rule id and version that was "
        "live at the moment of the check; approvals are bound to an immutable content "
        "version and voided by a trigger when that version changes."
    ),
)

# The Flutter web build runs on a different origin. Prototype-only, and the README
# says so: this is not a shipped CORS policy.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

for router in ROUTERS:
    app.include_router(router)


@app.exception_handler(StarletteHTTPException)
async def http_error(_request, exc: StarletteHTTPException):
    """HTTP errors go through SafeJSONResponse too. Starlette's default handler
    serialises the detail with plain json.dumps, which turns a helpful 409 about a
    UUID-shaped finding id into a 500."""
    return SafeJSONResponse({"detail": exc.detail}, status_code=exc.status_code,
                            headers=getattr(exc, "headers", None))


@app.exception_handler(CheckViolation)
async def schema_refused(_request, exc: CheckViolation):
    """A constraint refused the write. That is the system working, so say what it said."""
    return JSONResponse(status_code=422, content={"detail": str(exc).splitlines()[0]})


@app.exception_handler(UniqueViolation)
async def already_exists(_request, exc: UniqueViolation):
    return JSONResponse(status_code=409, content={"detail": str(exc).splitlines()[0]})
