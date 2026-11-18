# BrandGuard project guide

## Folder map

```text
BrandGuard-Fullstack/
  mobile/                         only Flutter application root
    lib/app/                      app entry, theme and routes
    lib/core/auth/                in-memory token/session state; demo autofill only
    lib/core/network/             bearer API client, refresh and file picker
    lib/features/auth/            server login/signup/recovery request
    lib/features/dashboard/       live scoped dashboard
    lib/features/checks/          exact-text editor, drafts, upload and findings
    lib/features/reviews/         exact-content human review
    lib/features/guidelines/      shared CRUD library/rules/fact sources
    lib/features/drafts/          private durable draft list
    lib/features/analytics/       live copyable reports
    lib/features/workspace/       history/audit/receipts hub
    lib/features/notifications/   durable in-app read state
    lib/features/profile/         actual server identity + logout
    test/                         mocked-client unit and phone-size widget tests
  backend/
    app/auth_service.py           local password/token or Supabase Auth adapter
    app/database.py               transactional SQLite/PostgreSQL repository
    app/storage.py                repository interface + legacy JSON test adapter
    app/routers/                  authentication, library, drafts/activity, files,
                                  checks, reviews, receipts, audit, reset page
    app/checks/deterministic/      versioned regex checks with execution budget
    app/checks/llm/                passage retrieval + validated provider output
    data/                         seed configuration; runtime SQL/secret/uploads ignored
    tests/                        inherited workflow regression tests, JSON adapter
    tests_secure/                 actual bearer+SQL workflows; mocked provider contracts
    migrations/001_core.sql        versioned initial PostgreSQL schema
    supabase/002_private_storage.sql  Supabase-only grants/bucket/Storage policies
    manage.py                     trusted init/migrate/create-user/backup/restore
    smoke_test.py                 real HTTP checks against a running isolated API
    .env.example                  server config placeholders, never real secrets
  docs/                           cloud/AI setup and this guide
  validation/                     evidence and limitations for this release
  start_backend.py / START_BACKEND.bat
```

Local sample analytics/governance stores were removed from this upgrade. Shared
preferences are for remembering an email/UI values, not password/token authority.
Roles come from the authenticated server user. Session tokens stay in memory and
normal JSON API requests retry once after token refresh. No saved-login claim.

## Main API groups

All private groups require `Authorization: Bearer ACCESS_TOKEN`; public ID/role
headers are rejected. Public routes include health, auth config/login/signup/refresh,
recovery request, recovery form and brand-rule version metadata.

| Group | Endpoints / behavior |
|---|---|
| Auth | `POST /api/v1/auth/login`, `/signup`, `/refresh`, `/recover`; `GET /me`, `/config`; `POST /logout`; `PUT /password` |
| Library | `GET/POST /api/v1/library/{guidelines,facts,rules}`; `PUT/DELETE /{kind}/{id}`; reads authenticated, mutations reviewer/admin |
| Files | `POST /api/v1/files`; `GET /files/{id}` extracted-text preview; `GET /files/{id}/download`; `?as_fact=true` reviewer-only |
| Drafts | `GET/POST /api/v1/drafts`; `PUT/DELETE /drafts/{id}`; own drafts only; optional `expected_revision` for conflict detection |
| Checks | `POST /api/v1/brand/check`; `POST /brand/{id}/versions` owner-only recheck; optional `expected_version` |
| Reviews | `GET /api/v1/reviews[?status=pending]`; `PATCH /reviews/{id}/decision`; independent reviewer/admin only |
| Verification | `POST /api/v1/approvals/verify`; exact brand/content/current rules/decision required |
| Evidence | `GET /api/v1/receipts/`, `/receipts/{id}`, `/audit`, `/history`; access-scoped |
| Activity | `GET /api/v1/analytics`, `/notifications`, `/system/status`; patch/delete notification state |

FastAPI `/docs` is the source of truth for request schemas and response details.
The mobile report is selectable/copyable live text, not a scheduled PDF/email service.
Notifications are stored in SQL and manually refreshed; no push/realtime delivery.

## Database/transaction model

Default SQLite database is `backend/data/brandguard.sqlite3`. PostgreSQL/Supabase
uses `DATABASE_URL`. Lists are individually keyed rows in `bg_entities` with
collection/entity ID/position/JSON payload; configuration objects are `bg_documents`.
This is real SQL persistence and atomic multi-collection workflow writes, **not**
a normalized per-domain/tenant schema. Updates currently rewrite a collection.

One nested transaction is shared through the repository. SQLite uses BEGIN IMMEDIATE;
PostgreSQL uses a transaction-scoped advisory lock plus the in-process lock. An
exception rolls back the entire workflow rather than leaving a half-written check,
receipt/audit entry. This favors correctness over concurrency/large data volume.
Use reviewed migrations, domain indexes/pagination and a job queue before scaling.

Seed JSON files remain only for starter rules and inherited regression fixtures.
They are not where the upgraded app stores live records. Old standalone JSON demo
records are **not automatically imported**; keep originals/backups intact.

File objects and SQL metadata cannot share an ACID transaction across Supabase
Storage. Failed uploads can require orphan-object cleanup. This source has no
object-deletion/retention worker. Removing a draft reference does not delete a file.
Local file storage requires a persistent disk; cloud mode stores objects in Supabase.

## Workflow integrity

- Scans and human approval are separate: scan passed/findings vs pending/approved/rejected.
- Exact submitted text is SHA-256 hashed; edits rerun current rules and AI, create
  a new version/receipt and clear an older decision.
- `expected_version` rejects stale edits/reviews. Rule snapshots are immutable;
  rule edits invalidate older-rules approval verification.
- Read protection covers checks, receipts, drafts, file previews/downloads,
  history, analytics and notifications. Reviewer/admin can inspect submissions;
  own private drafts remain private. Self-review is prohibited.
- AI source quotes/hashes are evidence records, not proof of semantic correctness.
- Rejection plus note is available; a separate Request Changes state is not.

## Auth/security and production boundaries

Local mode uses salted PBKDF2-SHA256 (600,000 rounds), 30-minute access JWTs,
7-day hashed/rotating refresh sessions and database-backed logout revocation. Local
signing secret is auto-generated with restricted filesystem permissions unless
`JWT_SECRET` is configured. For multi-worker/multi-host local-auth deployment, set
one strong secret securely rather than relying on a shared secret-file race.

Public signup cannot choose a role. CLI provisioning is a trusted administrative
action. Supabase mode validates the remote user and trusts application role only
from server-managed app_metadata. The new backend never enables demo ID headers
from an environment flag; inherited JSON tests explicitly monkeypatch that adapter.

Basic auth attempt limits are process-local, not distributed. External rate limiting,
TLS, reverse-proxy limits, stable database secrets/least privilege, periodic backups,
retention/deletion, monitoring, vulnerability review and real device tests remain
deployment responsibilities. Do not call this source production-security certified.
The library/reviewer workspace is global, not multi-tenant per organization.

## Backup and restore

Trusted backend terminal:

```sh
python manage.py backup --output /private/path/backup.json
python manage.py restore --input /private/path/backup.json --confirm-overwrite
```

Database backup uses a consistent transaction, includes all repository rows and
creates a new restricted-permission file. Restore replaces repository rows in one
transaction. Stop writes before operational restore. **Backups include password
hashes and session metadata: encrypt/protect them, never attach to chat/release ZIPs.**
Back up private local uploads/Supabase objects and the local JWT secret separately.
For PostgreSQL also use platform backups/pg_dump and test restores/retention; an
application-level export is not a replacement for full database disaster recovery.

## Validation meaning

`tests/` preserves the legacy JSON workflow contract. `tests_secure/` additionally
exercises default SQL/bearer mode, permissions, rollback, concurrency, libraries,
drafts, files, notifications, backup restore and mocked provider contracts.
Mocks are marked explicitly; they do not verify cloud SMTP, RLS behavior, actual
provider output quality, hosted API, native APK/IPA or device file-picker behavior.
Release-specific commands/counts and any environment limitations are in validation/.
