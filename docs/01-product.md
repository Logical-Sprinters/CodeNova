# 01 · Product

## The problem, in one paragraph

A brand team writes a rule — "TaskFlow Pro costs $34 per user per month", "never promise a
guaranteed outcome". The rule lives in a PDF. Someone in an agency writes a post that says
$29 and guarantees results. The copy ships. Nobody notices for a month, and when someone
does, nobody can say which version of the guideline was in force, who approved the post, or
whether the approval covered the sentence that caused the problem. Review does not fail
because people are careless; it fails because the thing being reviewed and the rule doing
the reviewing are both moving.

## What BrandGuard does

Paste copy. BrandGuard checks it against the rules that are **live on that date**, quotes
the exact span that breaks each rule, cites the rule id, version and source page, and
offers three different repairs. A human approves, and that approval is bound to the
immutable content version it approved. Change one word afterwards and the approval is voided
by a database trigger, with the reason written into an append-only log.

## The user

| Role | Who | What they do here |
|---|---|---|
| creator | agency copywriter, social manager | pastes copy, sees findings, applies a repair or overrides with a reason |
| reviewer | brand manager | approves a version; acknowledges advisory findings in writing |
| admin | brand lead | holds the guidelines, sees which rules keep being overruled |

## The three differences

Everything else in this project is table stakes. These three are not.

**1. Every finding cites a rule version that was live at the moment of the check.**
Not "a rule matched", not a similarity score: `PRIC-002 v1`, effective 15 October, page 1 of
`taskflow-price-sheet-2026-Q2.pdf`. The database refuses a confirmed finding that cites a
rule which was not in force when the check ran (trigger `findings_require_live_rule`), so the
citation cannot be decoration.

**2. An approval is bound to an immutable version — editing voids it.**
The approval stores the SHA-256 of the text it approved. A new version fires a trigger that
flips the old approval to `VOID` and writes the reason into the audit log as `SYSTEM`. No
service call, no cron, no developer discipline: the guarantee is in SQL, so it survives every
future code path.

**3. Overrides become clarity tickets against the rule that caused them.**
When a person overrules a finding they must say why (minimum three characters, enforced in
the schema). Those reasons accumulate per rule version in `v_clarity_tickets`. A rule that
is overruled five times is not a rule problem, it is a wording problem — and this is the
first time anyone can see it.

## What it deliberately refuses to do

- **It never treats "unsupported" as "false".** Grey findings do not block approval. The
  absence of evidence is not evidence of a broken rule, and software that confuses the two
  teaches people to click past it.
- **It never shows a confidence percentage as proof of truth.** Confidence is about the
  system; truth is about the copy. Every figure in the UI is a database field.
- **It never guesses when two live rules contradict each other.** `TONE-001` says open with
  a question; `TONE-002` says never do that. Both are live. The product says so and escalates
  to a named human — a linter that silently picks one is the failure being replaced.
- **It never claims a certification, a customer, or a metric it does not have.**

## Scope

| In | Out |
|---|---|
| paste-and-check for marketing copy | document ingestion, OCR, PDF parsing |
| price, naming, absolute-claim and terminology rules | image/visual analysis, tone judgement |
| three repairs per finding | generative copywriting |
| reviewer approval bound to a hash | e-signatures, legal attestation |
| append-only audit log | blockchain, distributed ledger claims |
| role checks server-side and in SQL | SSO, SCIM, multi-tenant isolation |
| one Flutter app, phone and laptop | native iOS, desktop installers, offline mode |

## The sentence that should survive a viva

> An approval is bound to an immutable content version; change the content and it dies —
> enforced by a trigger, not by policy.

## Where this came from

BrandGuard was built for **CodeNova**, an organising body running a short build sprint. It
is a prototype in the honest sense: the invariants are real and tested, and everything in
[06-limitations.md](06-limitations.md) is also real.
