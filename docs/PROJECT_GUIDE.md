# BrandGuard Project Guide (v3.0.0 / Round 3)

## Folder Map

```text
CodeNova/
  mobile/                               Flutter client root (source of truth for mobile + web)
    lib/app/                            Entry point, Executive Precision theme, routes, 5-tab shell
    lib/core/auth/                      In-memory session/token state; local-only demo autofill
    lib/core/network/                   Bearer API client, token refresh, cross-platform file picker
    lib/features/auth/                  Sign in, signup, password recovery
    lib/features/dashboard/             Live brand-scoped dashboard
    lib/features/checks/                Exact-text editor, live preflight, temporal/channel, multimodal upload, grounded findings
    lib/features/reviews/               Independent human review queue & decision sheet
    lib/features/approvals/             Cryptographic approval verification, file re-check & inline diff
    lib/features/governance/            Conflict resolution queue & clarity tickets screen
    lib/features/guidelines/            Brand guidelines, temporal/visual rules + logo template upload, verified fact sources
    lib/features/drafts/                Private versioned drafts
    lib/features/analytics/             Live copyable analytics & brand drill-down
    lib/features/workspace/             Workspace hub, version history, audit ledger
    lib/features/receipts/              Structured processing receipts with hash chain & diff view
    lib/features/notifications/         In-app notifications with read/delete state
    lib/features/profile/               Full My profile identity/session sheet, display name, preferences, logout
    test/                               Mocked-client unit, 5-viewport layout & Round 3 UI tests (124 tests)
  backend/                              FastAPI backend (Python 3.11+, tested on 3.13)
    app/auth_service.py                 Local PBKDF2/JWT or Supabase Auth adapter
    app/database.py                     Transactional SQLite / PostgreSQL repository (`bg_entities`, `bg_documents`)
    app/storage.py                      Repository interface + JSON test adapter
    app/rules_store/store.py            Versioned, temporal (`effective_from`/`expires_at`), channel-scoped rules
    app/approval/store.py               Immutable check versions, SHA-256 content/receipt hashes, rule-diff verification
    app/audit/store.py                  Append-only governance audit ledger
    app/overrides/store.py              Coded finding overrides + friction-based clarity ticket aggregator
    app/receipts/store.py               Tamper-evident receipt builder & hash chain verification
    app/checks/deterministic/engine.py  Versioned regex engine emitting verbatim rule quotes
    app/checks/grounding.py             Strict server-side grounding verifier (drops ungrounded findings)
    app/checks/conflicts.py             Active rule/fact `topic_key` contradiction detector & resolution store
    app/checks/llm/verifier.py          Passage retrieval over verified facts + strict schema AI verifier
    app/checks/visual/inspector.py      Image metadata, Tesseract OCR, dominant palette (`VIS-02`), logo pHash (`VIS-05`), Vision AI
    app/routers/                        authentication, brand, conflicts, email_delivery, files, library, overrides, receipts, recovery, reviews, workspace, audit
    data/brand_rules.json               Starter versioned rules with `rule_text`, temporal bounds, visual palettes
    tests/                              Inherited workflow regression tests (29 functions)
    tests_secure/                       SQL/bearer security, grounding, temporal, overrides, conflicts, OCR/visual, provider contracts (66 functions; 142 total pytest cases across both suites)
    migrations/001_core.sql             PostgreSQL schema with RLS
    supabase/002_private_storage.sql    Supabase Storage bucket & owner/reviewer policies
    manage.py                           CLI init/migrate/create-user/backup/restore
    smoke_test.py                       HTTP smoke verification against isolated local backend
    .env.example                        Environment configuration template (no secrets)
  browser_preview/                      Compiled Flutter `--no-web-resources-cdn` output served same-origin by `app.web`
  docs/                                 Project, AI, and Supabase guides
  validation/                           Historical v2.0.1 / Antideploy validation evidence
  Dockerfile / serve.py                 Production non-root Python 3.13 + tesseract-ocr container & entrypoint
  start_backend.py                      Local Python 3.11+ venv setup & Uvicorn launcher
```

## Runtime & Environment Requirements

- **Python 3.11+** (tested on Python 3.13; `fastapi==0.163.1` and `SQLAlchemy==2.1.8` do not support Python 3.10).
- **Optional OCR binary:** `tesseract` (`tesseract-ocr` on Linux/Docker, Tesseract-OCR on Windows, or `TESSERACT_CMD`). When absent, image uploads still run metadata, dominant color (`VIS-02`), and logo hash (`VIS-05`) checks while `ocr_status` honestly reports unavailability.

## Main API Groups

All private endpoints require `Authorization: Bearer ACCESS_TOKEN`; forged user/role headers are rejected.

| Group | Endpoints / Behavior |
|---|---|
| **Auth & Profile** | `POST /api/v1/auth/login`, `/signup`, `/refresh`, `/recover`, `/logout`; `GET /me`, `/config`; `PATCH /profile`; `GET/PUT /preferences`; `PUT /password` |
| **Library** | `GET/POST/PUT/DELETE /api/v1/library/{guidelines,facts,rules}`; `POST /api/v1/library/rules/{rule_id}/logo-template` (reviewer/admin mutations) |
| **Files & Visual** | `POST /api/v1/files` (TXT, MD, text PDF, PNG, JPG, JPEG, WEBP; `?as_fact=true` reviewer-only); `GET /files/{id}`, `/files/{id}/download` |
| **Drafts** | `GET/POST/PUT/DELETE /api/v1/drafts` (owner-only, optional `expected_revision`) |
| **Checks & Preflight** | `POST /api/v1/brand/preflight` (stateless editor preflight); `POST /api/v1/brand/check`, `POST /brand/{id}/versions` (`check_at`, `channel`, `content_type`, `asset_ids`), `GET /brand/rules/{brand_name}` |
| **Conflicts** | `GET /api/v1/conflicts/`, `GET /conflicts/{id}`, `POST /conflicts/{id}/resolve` (`auto_recheck` support, reviewer/admin) |
| **Reviews & Overrides** | `GET /api/v1/reviews[?status=pending\|approved\|rejected\|paused_conflict]`; `PATCH /reviews/{id}/decision`; `POST /reviews/{id}/findings/{fid}/override`; `GET /overrides`; `GET /clarity-tickets`; `PATCH /clarity-tickets/{id}` |
| **Verification & Evidence** | `POST /api/v1/approvals/verify`, `POST /api/v1/approvals/verify-upload`; `GET /api/v1/receipts/`, `/receipts/{id}`, `/audit`, `/history` |
| **Activity** | `GET /api/v1/analytics`, `/notifications`, `/system/status`; `PATCH/DELETE /notifications` |

## Database & Transaction Model

- Default SQLite database: `backend/data/brandguard.sqlite3`. Cloud mode uses PostgreSQL via `DATABASE_URL`.
- Entities are stored in `bg_entities` and singleton docs in `bg_documents` under a single shared transaction (`BEGIN IMMEDIATE` on SQLite; transaction-scoped advisory lock on PostgreSQL) so multi-collection updates (check + receipt + audit + notifications) commit or roll back atomically.
- Cross-service file objects in Supabase Storage are uploaded outside the SQL transaction; failed operations leave no partial SQL references, though orphan storage cleanup is not automated by a background worker.

## Workflow & Grounding Invariants

1. **No finding without evidence:** Deterministic, visual, and AI findings must cite an active `rule_id`, matching `rule_version`, a verbatim `rule_quote` from `rule_text` (or verified fact), and a valid content/OCR span or visual payload. `filter_grounded_findings()` enforces this both when running a check and before returning records to reviewers.
2. **Temporal validity:** Rules and Fact Sources respect `effective_from <= check_at < expires_at`, `supersedes`, and `channel` scoping.
3. **Conflict abstention:** Contradictory active rules/facts on the same `topic_key` pause the check (`abstained_conflict` / `paused_conflict`) until resolved by a reviewer.
4. **Overrides never auto-mutate rules:** Coded finding overrides record telemetry and aggregate repeated friction into Clarity Tickets; rule changes still require explicit reviewer versioning.
5. **Version & hash binding:** Content is SHA-256 hashed; any edit creates a new version, voids prior approval seals, and surfaces word-level diffs plus exact rule diffs during verification.
6. **Separation of duties:** Self-review is blocked (`409`); public signup can only register Creators.

## Backup & Restore

```bash
cd backend
python manage.py backup --output /private/path/backup.json
python manage.py restore --input /private/path/backup.json --confirm-overwrite
```
Backups contain password hashes and session metadata—store encrypted and never commit or share. Use PostgreSQL snapshots (`pg_dump`) alongside Storage backups in production.
