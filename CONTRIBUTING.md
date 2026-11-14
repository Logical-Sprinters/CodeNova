# Contributing

This project makes specific, checkable claims. A change is welcome if it keeps them true.

## Before you change anything

```bash
make up && make db && make db-test      # 28 of 28
make api                                # in one terminal
python scripts/smoke.py                 # 14 of 14, in another
```

If those two do not pass **before** your change, you are not fixing the thing you think you
are fixing.

## The five rules

1. **A guarantee belongs in SQL.** If the change adds a rule that must always hold ("an
   approval needs X", "this can never be edited"), write it as a constraint or a trigger and
   add an assertion. Do not add it to a service method and hope every future route calls it.
2. **Never invent a number.** Every figure in the UI comes from an API field. If there is no
   field, render a dash or an empty state. This includes "illustrative" figures and
   placeholder percentages.
3. **Never claim a certification, integration or customer.** No SOC 2 badge, no "Okta ready",
   no logos. If it is not implemented and tested here, it does not go on a screen.
4. **`UNSUPPORTED` does not mean false, and it must never block.** The five statuses have
   fixed meanings in `backend/app/core/statuses.py` and `frontend/lib/app/theme.dart`. Adding
   a sixth status means changing both, the enum, and `docs/03-data-model.md`.
5. **`audit_log` is append-only.** Never add code that updates or deletes a row. The database
   will refuse, and it should.

## Style

| Area | Convention |
|---|---|
| Python | 4 spaces, type hints on public functions, `ruff` or `black` defaults |
| SQL | keywords upper case, one clause per line, a comment above anything non-obvious |
| Dart | `dart format`, single quotes, no colour literals outside `lib/app/theme.dart` |
| Markdown | one idea per paragraph, tables for comparisons, no marketing adjectives |
| Commits | `area: imperative summary` — `db:`, `api:`, `app:`, `docs:` |

## Adding a rule family to the checker

1. Add the detector in `backend/app/core/checker.py` (pattern + status + which rule ids).
2. Add the three repair templates in `backend/app/core/rewrites.py`.
3. Add a seed rule in `database/003_seed.sql` that the detector can cite.
4. Add a backend unit test in `backend/tests/test_checker.py`.
5. Add an assertion in `database/tests/001_assertions.sql` if the change touches an
   invariant.
6. Update `docs/02-architecture.md` (the detector table).

## What will be rejected

- A feature that cannot be demonstrated in four commands.
- Any new dependency in `frontend/pubspec.yaml` that is not load-bearing.
- Any change that makes a claim in the README less true, including by renaming a thing so
  the claim becomes quietly wrong.
