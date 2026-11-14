# Technical Requirements Document

**Status:** Technical requirements baseline. API and UI code in this repository
are still scaffolds.

## Technical stack

| Layer | Planned technology | Requirement |
| --- | --- | --- |
| Web | Next.js, React, TipTap | Character-range evidence highlights; routes for submit, review, rules, and audit. |
| API | FastAPI, Pydantic v2 | Typed request/response validation and explicit failure responses. |
| Shared contracts | JSON Schema | Single source for API validation and generated TypeScript/Pydantic types. |
| Relational store | PostgreSQL | Transactional rule versions, content versions, approvals, and audit records. |
| Semantic retrieval | pgvector | Keep retrieval scoped to the relational rule/version lifecycle. |
| Deterministic checks | Python, Pillow, OpenCV | Reproducible price, terminology, casing, asset-hash, contrast, and alt-text checks. |
| Semantic checks | LLM with strict JSON output | Limited to tone and claim analysis; output is untrusted until verified. |
| Approval | Canonical JSON and SHA-256 | Bind an approval to text, channel, and sorted asset fingerprints. |

## Functional technical requirements

### Rules

- Store each rule as a version with source reference, type, status, effective
  date, optional expiry, optional superseded version, risk tier, and channels.
- A proposed rule remains a draft until an admin confirms it.
- Retrieval must filter on channel, status, effective date, and expiry.
- A source conflict or expired source must be represented explicitly and
  escalated; do not pick a winner by model score or recency alone.

### Checks and five verifier gates

Run deterministic checks first, then any permitted scoped model checks. Before
persisting or displaying a candidate finding, apply these gates in order:

1. **Known rule:** the candidate's `rule_id` and version exist in the active
   rules supplied to the run; otherwise drop it.
2. **Exact evidence:** the quoted evidence is present in the cited rule text;
   otherwise drop it.
3. **Temporal validity:** the rule is effective and not expired/superseded for
   the submission date; otherwise escalate to an admin.
4. **Conflict:** if active applicable sources disagree, abstain and escalate.
5. **Emit:** only a candidate passing all gates becomes a finding with its
   verified evidence quote and character span.

The system must distinguish unsupported from false. High-risk claims are routed
to an authorised reviewer.

### Approval and audit

- Model approval states as `DRAFT`, `CHECKS_RUN`, `IN_REVIEW`, `APPROVED`, and
  `VOID`.
- Compute a canonical representation using stable key ordering, normalized
  whitespace/Unicode, and sorted asset fingerprints.
- Any change to text, channel, or assets after approval creates a new content
  version and voids the prior approval with a diff.
- Store audit actions for submission, check, edit, override, approval, and void.
  An override requires a non-empty reason; the audit log is append-only.
- Enforce separation of creator and reviewer on the server side.

### Processing receipt and privacy

Every model run has a receipt linking the submitted text and exact active rule
versions to redactions, retention terms, provider, and timestamp. Only send the
draft and rules relevant to its channel. Do not retain uploaded client artwork;
retain derived fingerprints only where needed for checks and approval hashes.

## Non-functional requirements

- Deterministic checks must be reproducible without a language model.
- API inputs and model outputs must be validated against shared typed contracts.
- State changes that create an approval, void, receipt, or audit event must be
  committed transactionally.
- Fail closed for invalid evidence, invalid signatures/hashes, and authorization
  failures; surface actionable abstention/escalation states rather than
  success-shaped fallbacks.
- Protect secrets with environment configuration; never commit real `.env`
  files.
- File upload limits, supported formats, malware handling, and retention periods
  must be specified before production deployment.

## Current decisions and open items

- Demo data is fictional TaskFlow content.
- API endpoint paths, authentication provider, exact upload limits, retention
  durations, model provider, embedding dimension, and deployment environment
  have not been selected in the submission. Do not invent these values in
  implementation; record decisions in `docs/decisions/`.
- The schema enables pgvector but does not choose an embedding dimension.
