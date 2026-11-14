# 02 · Architecture

Three tiers, one direction of dependency: the app talks to the API, the API talks to the
database, and **the database is the only tier allowed to guarantee anything**.

```
┌──────────────────────────────┐
│ Flutter app (phone + laptop) │   lib/features/*, lib/core/api.dart
│ no business rules            │   renders what the API returns; recomputes nothing
└──────────────┬───────────────┘
               │ HTTP · JSON · X-User-Id
┌──────────────▼───────────────┐
│ FastAPI                      │   backend/app/api (routes) → app/services → app/core
│ authorisation, orchestration │   app/core/checker.py is a pure function
└──────────────┬───────────────┘
               │ psycopg 3 · no ORM · explicit SQL
┌──────────────▼───────────────┐
│ PostgreSQL 16                │   database/001_schema.sql, 002_functions.sql
│ every invariant lives here   │   4 triggers, 3 functions, 2 views
└──────────────────────────────┘
```

## Why the invariants are in the database

A rule in a service method is a rule that a future route, a maintenance script, or a
psql session can skip. Each of the four guarantees in this project is written as a
`TRIGGER` or a `CHECK`, so it holds no matter who is writing:

| Guarantee | Enforced by | If it lived in Python |
|---|---|---|
| The content hash matches the text | `content_version_set_hash()` — `BEFORE INSERT` | a bug or a manual insert could store a hash that lies |
| A new version voids the old approval | `void_prior_approvals()` — `AFTER INSERT` | every code path would have to remember to call it |
| A confirmed finding cites a rule that was live at check time | `finding_requires_live_rule()` — `BEFORE INSERT` | the checker could cite anything and nobody would notice |
| Only an active non-author reviewer can approve | `approvals_require_authorised_reviewer()` — `BEFORE INSERT OR UPDATE` | an admin script could approve its own work |
| The audit log cannot be rewritten | `audit_log_is_append_only()` — `BEFORE UPDATE OR DELETE` | "we won't update it" is not a guarantee |

The API still checks roles and blocking findings — twice is the point: a clear 403 with a
sentence beats a stack trace, but the database is what makes it true.

## Request lifecycle: one check

`POST /content` with `{"text": "...", "channel": "social"}`

1. **Route** (`api/content.py`) validates the payload shape.
2. **Identity** (`deps.current_user`) reads `X-User-Id`, loads the user, refuses a
   deactivated account with 403.
3. **Service** (`services/content.create`):
   - inserts `content_items` (the thing being published),
   - inserts `content_versions` — **without a hash**; the trigger computes it,
   - writes `audit_log` `submitted`,
   - calls `run_checks`.
4. **Engine** (`core/checker.check`) — a pure function: `(text, channel, live_rules) →
   findings`. It never touches the database, so it is testable in isolation.
5. **Live rules** come from `live_rules_for_channel(channel, run.started_at)` — the
   database's definition of "in force at this instant", not a `WHERE status = 'ACTIVE'`.
6. **Persistence**: findings and their three repairs are inserted in one transaction with
   the check's outcome (`COMPLETED`, or `ABSTAINED` when every applicable rule contradicts
   another).
7. **Response**: the content id, the stored version, and a summary of the findings.

## Request lifecycle: the approval dying

1. A reviewer calls `POST /content/{id}/approve`.
2. The service collects unresolved blocking findings. If any exist → **409**, listing
   them so the UI can name them.
3. Otherwise it writes `approvals.state = 'APPROVED'` with the version's own hash. The
   trigger re-checks the role, the account, the author and the hash.
4. Later, anyone calls `POST /content/{id}/versions` with edited text.
5. `INSERT INTO content_versions` fires `void_prior_approvals()`, which flips the old
   approval to `VOID`, stores `previous_hash` and the new version number in `void_diff`,
   and writes an `audit_log` row with `actor_type = 'SYSTEM'`, `actor_id = NULL`.
6. The app shows that row. Nobody called an endpoint to void anything.

## The checker

`app/core/checker.py` — deterministic, ~200 lines, no network, no model.

| Detector | What it looks for | Status it produces |
|---|---|---|
| price | a `$` figure that differs from a live price-sensitive rule | `CONFIRMED_RULE_MATCH` |
| naming | the product written as two words (`TERM-001`) | `CONFIRMED_RULE_MATCH` |
| guarantee | "guaranteed", "100%", "never fails" (`CLAI-002`) | `NEEDS_AUTHORISED_REVIEWER` |
| leadership | "#1", "market leader" (`CLAI-001`) | `NEEDS_AUTHORISED_REVIEWER` |
| terminology | "project" where the guideline says workspace (`TERM-002`) | `AI_INTERPRETATION` |
| superlative | "fastest", "world-class" — with no rule at all | `UNSUPPORTED` |
| contradiction | `TONE-001` and `TONE-002` both live and opposed | `SOURCE_CONFLICT_OR_EXPIRED` |

Two properties matter more than coverage:

- **It cannot invent a rule.** Every finding carries a real `(rule_id, version)` that is
  in force, or it is explicitly an `UNSUPPORTED` finding with no rule at all.
- **It refuses to guess.** When two live rules contradict each other, the product says so
  and escalates. A linter that silently picks one is the failure mode this replaces.

Spans are Python code points. For the ASCII copy in the seed that equals Dart's UTF-16
offsets, so highlights land exactly; with emoji the two would drift. That is a documented
limit, not a surprise: [06-limitations.md](06-limitations.md).

## Why these choices

| Choice | Reason | Rejected alternative |
|---|---|---|
| No ORM | the SQL is the artefact being defended; an ORM hides it behind a second, weaker model | SQLAlchemy |
| Deterministic checker | works offline, cannot hallucinate, defensible in one sentence | LLM checks (kept in the roadmap, not in the demo path) |
| Hand-written models | 8 `fromJson` methods cost less than a codegen pipeline that can fail | `freezed` / `json_serializable` |
| One Flutter app | one codebase, two form factors; the fallback demo target costs nothing | separate Next.js web app |
| `http` only | every package is a build that can fail on someone else's machine | dio, riverpod, go_router |
| Header identity | honest about what is not built; the server still enforces roles | half-built JWT auth |
| Bundled Manrope | a runtime font fetch is a blank-looking demo on bad wifi | `google_fonts` |

## What is deliberately absent

Background jobs, queues, caches, websockets, file upload, OCR, embeddings, notifications,
multi-tenancy, i18n, theming beyond one palette. Each one is a week, and none of them is
in the eight-step story this project tells.
