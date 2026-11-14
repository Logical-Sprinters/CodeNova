# backend/

FastAPI, Python 3.12, psycopg 3. No ORM: the SQL in `../database/` is the source of truth
and this layer decides what to ask it and how to explain the answer.

```
app/
├── main.py            app, CORS, exception handlers, lifespan
├── config.py          DATABASE_URL, nothing secret (no model key: checks are deterministic)
├── db.py              one connection pool, dict rows, explicit SQL
├── deps.py            identity (X-User-Id) and the reviewer dependency
├── api/               six routers, thin: validate, call a service, translate errors
│   health · identity · guidelines · content · findings · review · audit
├── services/          everything that touches the database
│   content.py         create, version, run checks, detail
│   findings.py        accept a repair, override with a reason, clarity tickets
│   review.py          queue, approve
│   audit.py           write and read the append-only log
├── core/              pure functions, no database, no network
│   checker.py         text + channel + live rules → findings
│   rewrites.py        the three repair templates
│   statuses.py        the five statuses, and which two block
└── models/payloads.py request bodies (pydantic)
```

## Run

```bash
python -m venv .venv && source .venv/bin/activate    # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000
```

`http://localhost:8000/docs` is generated from the code. `GET /health` returns row counts, so
it proves the database is both reachable and seeded.

## Test

```bash
pytest -q                     # skips the database tests when DATABASE_URL is absent
python ../scripts/smoke.py    # the end-to-end story, against a running API
```

## Rules for this folder

1. **Routes stay thin.** Validation and error translation only; anything else is a service.
2. **No SQL in routes.** If a route needs a query, the service needs a function.
3. **Never re-implement a database invariant.** If the rule matters, it is a constraint; do
   not duplicate it here and then disagree with it.
4. **Never swallow a constraint's message.** A refused write is the system working — pass
   its words to the user, as in `the author of a version cannot approve it`.
