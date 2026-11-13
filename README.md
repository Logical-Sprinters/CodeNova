# BrandGuard

BrandGuard is a proposed pre-publication brand-governance tool. It checks
marketing content against approved, versioned rules, requires evidence for
findings, and binds human approval to the exact content version.

**Repository status:** planning and scaffold. The web app, API, migrations,
Docker services, and automated test commands are not implemented yet. Do not
treat the plans and schema as a deployed or production-ready system.

## Project documents

| Document | Purpose |
| --- | --- |
| [Product requirements](docs/prd.md) | Users, outcomes, features, scope, and acceptance principles. |
| [Technical requirements](docs/trd.md) | Stack and verifiable technical behaviors. |
| [Technical architecture](docs/architecture.md) | Components, data flow, and transaction boundaries. |
| [Application flow](docs/app-flow.md) | Roles, lifecycle, findings, and failure paths. |
| [Frontend specification](docs/frontend-specification.md) | Routes and UI/UX behavior. |
| [Backend schema](docs/backend-schema.md) | Relational model and integrity rules. |
| [Security and access](docs/security-access.md) | Role permissions, data handling, and controls. |
| [Threat model](docs/threat-model.md) | Assets, trust boundaries, threats, and mitigations. |
| [Implementation plan](docs/implementation-plan.md) | Round-based milestones and dependencies. |
| [Feature tickets](docs/feature-tickets.md) | Proposed F1-F11 backlog and acceptance criteria. |
| [Data contracts](docs/data-contracts.md) | Shared JSON Schema contracts and invariants. |
| [Contributing](CONTRIBUTING.md) | Workflow, tests, scope, and pull request expectations. |

## Planned stack

- Web: Next.js, React, and TipTap.
- API: FastAPI and Pydantic v2.
- Storage/retrieval: PostgreSQL and pgvector.
- Checks: deterministic Python/Pillow/OpenCV checks, then scoped strict-JSON
  model checks.

## Database schema

The initial PostgreSQL DDL is [`databases/schema.sql`](databases/schema.sql). It targets
a fresh database with pgvector available:

```sh
createdb brandguard
psql -d brandguard -v ON_ERROR_STOP=1 -f databases/schema.sql
```

This command has not been run in the current environment. The Compose file in
`databases/` and application entry points are placeholders; there is not yet a
complete local quick-start.

## Scope and demo data

The planned Round 2 MVP is F1-F8 and F11. F9 governance insights and F10 audit
export are deferred. TaskFlow is fictional; public demos must not include real
client artwork or unmeasured research claims.
