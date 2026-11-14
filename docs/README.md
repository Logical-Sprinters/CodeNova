# Documentation

Eight documents, in the order they are useful. Everything here describes **this
repository as it is**, including the parts that are unfinished.

| # | Document | Read it if you want to know |
|---|---|---|
| 01 | [Product](01-product.md) | what BrandGuard is, who it is for, and what it deliberately does not do |
| 02 | [Architecture](02-architecture.md) | how the three tiers fit together and where the request boundary is |
| 03 | [Data model](03-data-model.md) | every table, every enum, every invariant, and why it is in the schema |
| 04 | [API](04-api.md) | every endpoint, its payload and its failure modes |
| 05 | [Testing](05-testing.md) | what is proven and how to reproduce it in four commands |
| 06 | [Limitations](06-limitations.md) | what does not work, what is not built, and what closing it would cost |
| 07 | [Decisions](07-decisions.md) | the eight decisions that shaped the build, and what was rejected |
| — | [Run local](run-local.md) | copy-paste run book for Windows / PowerShell |

## The three-sentence version

BrandGuard checks marketing copy against approved, versioned brand rules, and every
finding it reports cites the exact rule version and quotes the exact span that caused it.
It refuses to guess: when two live rules contradict each other, or a claim has no rule
behind it, it says so and hands the decision to a named human rather than inventing
confidence. Approval is bound to an immutable content version, so the moment the copy
changes, the approval is voided by a database trigger and the audit log records who did
nothing and what happened anyway.

## What to check first, if you are reviewing this

1. `database/tests/001_assertions.sql` — 28 assertions, each of which fails if a product
   claim is false. Run `make db-test`; it prints one line per assertion.
2. `scripts/smoke.py` — 14 steps through the real API, ending with an approval being
   voided by a one-word edit. Run it after `make api`.
3. `database/002_functions.sql` — the four triggers. This is where the claims are true.
4. `docs/06-limitations.md` — read it before assuming anything else works.
