# BrandGuard

**Pre-publication brand governance.** Paste marketing copy; BrandGuard checks it against
the rules that are live **on that date**, quotes the exact span that breaks each rule,
cites the rule id and version, offers three repairs, and binds a human approval to the
immutable content version it approved — so editing the copy afterwards kills the approval,
enforced by the database rather than by policy.

One Flutter codebase for phone and laptop. FastAPI. PostgreSQL 16.

> **Status: working prototype, verified locally.** The schema, the API and the app are all
> implemented and were run end to end against a real PostgreSQL: **28/28 schema
> assertions**, **14/14 API tests**, **14/14 smoke-test steps**, `flutter analyze` clean,
> `flutter test` passing, and a release web build. CI repeats all of it on every push
> ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).
>
> **Zero customer interviews, zero pilot users, zero scored evaluation cases.** No
> compliance certification is claimed or implied. Known gaps are listed honestly in
> [docs/06-limitations.md](docs/06-limitations.md).

---

## Run it

Two entry points; pick the one for your machine. Neither needs `make`.

**Windows (PowerShell 5.1 or 7):**

```powershell
.\scripts\check-env.ps1        # what is installed, and the install command for what is not
.\scripts\dev-native.ps1      # native PostgreSQL 16: role + database + schema + 28 assertions
.\scripts\api.ps1             # API on http://localhost:8000  →  /docs   (second terminal)
python scripts\smoke.py        # the 14-step story                       (third terminal)
```

`check-env.ps1` first: it prints exactly which tools are missing rather than letting you find
out one command at a time.

**No Docker?** Neither path needs it. `dev-native.ps1` talks to a locally installed
PostgreSQL 16 — `winget install -e --id PostgreSQL.PostgreSQL.16`, then a **new** terminal,
then `dev-native.ps1`. Docker Desktop also works (`dev.ps1`) but needs WSL2, virtualisation
enabled in the BIOS and usually a reboot.

If PowerShell refuses to run the scripts:
`powershell -ExecutionPolicy Bypass -File .\scripts\check-env.ps1`

**macOS / Linux:**

```bash
make up && make db && make db-test    # postgres, schema → functions → seed, 28 assertions
make api                              # API on http://localhost:8000   (second terminal)
python scripts/smoke.py               # the 14-step story              (third terminal)
```

Then the app, either platform:

```bash
cd frontend && flutter pub get && flutter run -d chrome
```

First runs are slow — a Docker image pull, a `flutter pub get`, and a first build. Start
`dev.ps1` / `make up` and `flutter pub get` while you read the rest.

**Expect, exactly:** `28 of 28 passed` from the assertions, `all 14 steps passed` from the
smoke test. Anything else names the failing step.

**Windows notes, learned the hard way:** PowerShell 5.1 has no `&&` (7 does); `make` and
`psql` are not on PATH by default; the PostgreSQL installer does not always add itself to
PATH, so `dev-native.ps1` searches `C:\Program Files\PostgreSQL\*\bin` for you. The scripts
are the supported path, not a convenience. Full run book:
[docs/run-local.md](docs/run-local.md).

The `android/` and `web/` folders are committed scaffolding, so a clone runs without an
extra `flutter create` step. `lib/` is hand-written and is never generated.

---

## What it actually does

```
paste copy ──▶ check against rules live at this moment ──▶ findings
                                                             │
                        ┌────────────────────────────────────┘
                        ▼
   each finding: 5-way status · the exact quote · rule id + version + source page
                 three repairs (A surgical · B brand-balanced · C channel-native)
                        │
        repair or override (with a reason)  ──▶ new immutable content version
                        │
                        ▼
        reviewer approves ──▶ approval bound to sha256 of that version
                        │
        anyone edits one word ──▶ trigger voids the approval · audit log says SYSTEM
```

### The five finding statuses

| Status | Colour | Means | Blocks approval |
|---|---|---|---|
| `CONFIRMED_RULE_MATCH` | red | a live rule is broken, deterministically | **yes** |
| `SOURCE_CONFLICT_OR_EXPIRED` | orange | live rules contradict each other, or the source lapsed | **yes** |
| `NEEDS_AUTHORISED_REVIEWER` | purple | a person must decide; no rule can | no |
| `AI_INTERPRETATION` | amber | our reading of the copy, labelled as our reading | no |
| `UNSUPPORTED` | grey | nothing backs this claim — **which does not mean it is false** | no |

Grey never becomes red. No screen shows a confidence percentage as proof of truth. Every
number in the interface comes from an API field; when there is no field, the screen says so.

### Three things that are enforced in SQL, not in code

1. **A rule is live only inside its window and until something supersedes it.**
   `live_rules_at(ts)` — never `WHERE status = 'ACTIVE'`, which lies the moment a row
   drifts. It also answers historical questions correctly: a rule superseded last week was
   live last month, and a finding from last month is still judged honestly.

2. **A finding may not cite a rule that was not live when the check ran.**
   The trigger `findings_require_live_rule` raises, so `CONFIRMED_RULE_MATCH` cannot be
   decoration.

3. **A new content version voids the standing approval.** `void_prior_approvals()` fires
   on insert, writes `state = 'VOID'` with the previous hash and the new version number,
   and records an `audit_log` row as `SYSTEM`. The API does not know it happened.

Plus: the content hash is computed by the database (`content_hash()` + a `BEFORE INSERT`
trigger, so a caller-supplied hash that disagrees is refused), an approval requires an
active non-author reviewer, and `audit_log` refuses `UPDATE` and `DELETE`.

---

## Repository map

```
database/     001_schema · 002_functions · 003_seed · tests/001_assertions
backend/      FastAPI · no ORM · app/{api,core,models,services}
frontend/     Flutter · one codebase, phone and laptop · lib/features/*
scripts/      smoke.py (end-to-end proof), dev.sh, dev.ps1
design/       tokens.json — Executive Precision colours, type, spacing
docs/         01-product · 02-architecture · 03-data-model · 04-api
              05-testing · 06-limitations · 07-decisions · run-local
```

Each folder has a README explaining what belongs there and what does not.

---

## Honest limitations

- **Identity is a header, not a login.** `X-User-Id` names the caller; the server reads
  their role from `users` on every request, and the database re-checks it. This is not
  authentication and it is not shipped as if it were.
- **Checks are deterministic** phrase and price matching — no model, no embeddings. It
  cannot invent a rule (the point) and it will miss unusually phrased copy (the cost).
  Visual and tone rules exist in the guidelines screen and are not evaluated.
- **CORS is open** so the Flutter web build can talk to the API. Prototype only.
- **One tenant.** No `tenant_id`, no row-level security, no claim of multi-tenancy.
- **Approvals are not append-only.** Each approval is *bound* to one immutable version by
  its hash; a new version voids it, and the void is written to an append-only log. That
  sentence is the accurate one, and the README uses it everywhere.
- **No SOC-2, no SSO, no Cloudflare.** Anything of that shape was deliberately removed.

The full list, with what each one would cost to close:
[docs/06-limitations.md](docs/06-limitations.md).

---

## Documentation

| Read this | For |
|---|---|
| [docs/README.md](docs/README.md) | the index, and the order that makes sense |
| [docs/01-product.md](docs/01-product.md) | problem, user, the three differences, scope |
| [docs/02-architecture.md](docs/02-architecture.md) | components, request lifecycle, why these choices |
| [docs/03-data-model.md](docs/03-data-model.md) | tables, enums, every invariant, ERD |
| [docs/04-api.md](docs/04-api.md) | every endpoint with request and response |
| [docs/05-testing.md](docs/05-testing.md) | what is proven, how to run it, what is not |
| [docs/06-limitations.md](docs/06-limitations.md) | what this does not do, and why |
| [docs/07-decisions.md](docs/07-decisions.md) | the eight decisions and what was rejected |
| [docs/run-local.md](docs/run-local.md) | Windows / PowerShell run book |
| [CONTRIBUTING.md](CONTRIBUTING.md) | how to change this without breaking its claims |

## Licence

MIT — see [LICENSE](LICENSE).
