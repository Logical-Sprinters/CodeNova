# Implementation Plan

This plan reflects the three rounds and feature scope in the submission. It is
a proposed sequence, not a statement that these milestones are complete.

## Current repository baseline

The repository currently contains a project scaffold, starter documentation,
and empty application/test placeholders. It does not yet contain a working web
app, API, database migrations, or runnable test commands. The database DDL and
contracts added alongside this plan are starting artifacts and still require
validation in PostgreSQL and implementation review.

## Round 1 — Plan and research

**Goal:** validate the problem and freeze the contracts/tests before coding.

- Conduct consent-based interviews and draft/review-thread audits.
- Keep completed counts truthful; the submission's initial counts are zero.
- Commit shared data contracts and source/version semantics.
- Create and freeze golden grounding, conflict, edit-void, and friction cases.
- Record architecture and security decisions as ADRs.

**Exit:** consent materials ready; contracts reviewed; golden input/expected
output cases frozen; no invented research results.

## Round 2 — Judged MVP

**Goal:** a judge can run the critical workflow unaided using fictional TaskFlow
data.

### Delivery sequence and dependencies

1. **Foundation:** local PostgreSQL/pgvector setup, API contract validation,
   migrations, and fictional fixtures.
2. **F1 + F2:** guideline ingestion/admin confirmation, then temporal,
   versioned rules. Rule checks depend on this source of truth.
3. **F3 + F4:** channel-aware context and deterministic checks (price, terms,
   casing, image fingerprint/contrast/alt text).
4. **F5:** scoped tone/claim checks with strict JSON; do not use model output as
   trusted data.
5. **F6:** five-gate verifier, abstention, and escalation. This must gate all
   findings before they reach the review UI.
6. **F7:** submission and review studio with citations, rewrites, history, and
   user-visible failure states.
7. **F8 + F11:** canonical hash approval/void behavior and a processing receipt
   for every AI run.
8. **Integration:** seed fictional TaskFlow data, one-command local start,
   golden suite, and end-to-end demo.

### Round 2 exit criteria

- F1-F8 and F11 work in one end-to-end flow.
- All golden acceptance bars in `docs/feature-tickets.md` pass.
- No unsupported claim is presented as false; no finding bypasses the verifier.
- Self-approval is rejected; post-approval edits void and audit the old version.
- Every model run has a receipt; demo inputs are fictional.
- A fresh clone can start the app using documented commands.

## Round 3 — Finish and pilot

- F9: aggregate override friction into guideline-clarity tickets, never
  automatic rule rewrites.
- F10: one-click audit export with access control and privacy review.
- Complete threat model, licence register, usability pass with three real
  reviewers, and demo video.
- Run a pilot with one agency only after consent, retention, support, and
  incident-response decisions are complete.
- Report pilot metrics as measured values; do not substitute targets for data.

## Change control

Keep `main` demoable and merge through reviewed pull requests. Reorder work only
when an issue records the dependency, acceptance change, risks, and impact on the
golden suite.
