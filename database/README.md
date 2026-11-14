# database/

PostgreSQL 16. Four files, one order, no migration framework.

| # | File | What it is |
|---|---|---|
| 1 | `001_schema.sql` | 11 tables, 10 enums, 9 invariants as `CHECK`s and unique indexes |
| 2 | `002_functions.sql` | 4 triggers, 3 functions, 2 views — all the behaviour |
| 3 | `003_seed.sql` | the demo world: 4 users (one deactivated), 12 rule versions, 3 content items, 5 findings |
| 4 | `tests/001_assertions.sql` | 28 assertions, run in a transaction, rolled back |

## Run

```bash
make up && make db        # start Postgres, then apply 001 → 002 → 003
make db-test              # 28 of 28 passed
```

## The three files, and why they are separate

`001_schema.sql` can be read in one sitting and describes the shape of the data: users,
guideline documents, rule versions, content items, content versions, check runs, findings,
repairs, approvals, overrides, audit log.

`002_functions.sql` is the behaviour, and every claim the project makes is in it:

| Function / trigger | Claim |
|---|---|
| `content_hash()` + `content_version_set_hash()` | the hash of a version is computed by the database; a supplied hash that disagrees is refused |
| `live_rules_at()` | what was in force at a moment in time, including correct answers about the past |
| `live_rules_for_channel()` | the only query the checker is allowed to use |
| `refresh_rule_lifecycle()` | tidy the `status` column for humans (not used by the checker) |
| `void_prior_approvals()` | a new content version voids the standing approval and writes a `SYSTEM` audit row |
| `finding_requires_live_rule()` | a confirmed finding cannot cite a rule that was not live at check time |
| `approvals_require_authorised_reviewer()` | an approval needs an active, non-author reviewer and the version's own hash |
| `audit_log_is_append_only()` | `UPDATE` and `DELETE` on the audit log raise |
| `v_clarity_tickets` | rules that keep being overruled, as a query |

`003_seed.sql` is relative to `CURRENT_DATE`, so the demo works in any month. It includes
the cases that make the product interesting: a superseded rule whose own window is still
open, an `ACTIVE` rule that expired weeks ago, two live rules that contradict each other, and
a `DRAFT` rule with no confirming human.

## Conventions

- Files are numbered because order matters; `002` expects `001`.
- Everything is idempotent enough to re-run on a fresh database. For a genuinely clean
  state: `docker compose down -v && docker compose up -d && make db`.
- No `pgvector`, no extensions beyond `pgcrypto`. Retrieval is a channel/type filter, so
  there is nothing to embed.
