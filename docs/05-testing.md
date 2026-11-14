# 05 · Testing

Two layers, both runnable in seconds, both testing behaviour rather than implementation.
There is no mocking anywhere: the schema tests use a real PostgreSQL, and the smoke script
uses the real API over HTTP.

```bash
make db-test              # 28 schema assertions        → 28 of 28 passed
python scripts/smoke.py   # 14 end-to-end API steps      → all 14 steps passed
cd backend && pytest -q   # API unit + integration tests
cd frontend && flutter analyze && flutter test
```

## Layer 1 — schema assertions (`database/tests/001_assertions.sql`)

28 assertions written as SQL, wrapped in one transaction that is **rolled back**, so the
suite is safe against a live demo database. Each one is a product claim; if it fails, the
claim in the README is false.

| Group | Assertions | What they pin down |
|---|---|---|
| Liveness (A01–A06) | 6 | a superseded rule is not live while its own window is open; an ACTIVE row past its expiry is not live; a DRAFT is never live; 100 days ago `PRIC-001` *was* live — history is answered honestly; channel filtering works |
| Hashing (A07–A10) | 4 | whitespace-insensitive canonicalisation; 64-char sha256 that depends on the channel; the seed's null hashes were filled by the trigger; a supplied mismatched hash is refused |
| Findings (A11–A12) | 2 | a `CONFIRMED_RULE_MATCH` cannot cite a superseded rule; the same citation *is* allowed as `SOURCE_CONFLICT_OR_EXPIRED` |
| Repairs (A13) | 1 | a second accepted repair for one finding is refused |
| Approval (A14–A18) | 5 | a creator cannot approve; a deactivated reviewer cannot approve; an author cannot approve their own version even as an admin; a wrong hash is refused; an honest approval succeeds |
| The void (A19–A21) | 3 | a new version flips the approval to `VOID`, with the previous hash and the new version number, and the audit row is `SYSTEM` |
| Audit log (A22–A23) | 2 | `UPDATE` and `DELETE` on `audit_log` both raise |
| Rules and overrides (A24–A28) | 5 | price-sensitive rules must expire; a rule cannot be ACTIVE without a confirmer; an override needs a real reason; overrides become clarity tickets; `refresh_rule_lifecycle()` tidies the drifted row |

Refusals are asserted by *expecting the exception*: a test that passes when the database
says no is worth more than one that passes when it says yes.

## Layer 2 — the end-to-end story (`scripts/smoke.py`)

14 steps over HTTP against a running stack, printing what it actually saw. It is the
documented demo, executed:

1. the API is up and the database is seeded
2. a superseded rule is not live; its replacement is
3. the demo copy produces findings, each with a rule, a version and a character span
4. every finding offers three repairs
5. a creator cannot approve (403)
6. a deactivated reviewer cannot act (403)
7. a blocking finding stops the approval (409)
8. accepting a repair creates version 2 and re-checks it
9. two live tone rules that contradict each other block approval rather than being guessed
10. an override becomes a clarity ticket against that rule version
11. the reviewer approves, bound to the content hash
12. **one changed word voids the approval**, by trigger
13. the ledger explains it, attributed to `SYSTEM`

Useful as a check, not just a demo: run it after any change to the schema, the checker or
the services.

## Layer 3 — unit and widget tests

`backend/tests/`
- `test_checker.py` — the engine as a pure function: prices, absolute claims, the
  contradiction case, and that an `UNSUPPORTED` finding never blocks approval.
- `test_api.py` — needs `DATABASE_URL`; skips cleanly without one rather than failing on a
  machine that has no database.

`frontend/test/widget_test.dart`
- every finding status has a human label and a colour;
- only `CONFIRMED_RULE_MATCH` and `SOURCE_CONFLICT_OR_EXPIRED` block, and `UNSUPPORTED`
  explicitly does not.

## What is *not* tested

Named honestly, because a missing test is a fact about the project:

- **No UI rendering tests.** Layout is verified by running the app. `flutter analyze` is
  clean and the widget test covers the vocabulary, not the screens.
- **No load, concurrency or performance testing.** There is one instance and one database.
- **No browser automation.** The Flutter web build compiles; nobody drives it in CI.
- **No security testing** beyond role checks. Identity is a header; see limitations.
- **No coverage number.** A percentage would imply the suite tests everything worth
  testing, and it does not.
