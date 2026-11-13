# Feature Ticket Backlog

This is a proposed backlog extracted from the Round 1 submission, not a list of
issues already created in GitHub. F1-F8 and F11 are the Round 2 MVP; F9 and F10
are deferred to Round 3.

## Round 2 MVP

### F1 — Rule ingestion and admin confirmation

**Story:** As an admin, I can ingest a guideline/fact source and review proposed
rules before activation.

**Acceptance:** Preserve source file/page; proposed rules are drafts; only an
admin-confirmed rule version can become active; extraction failures are shown
and do not silently create rules.

### F2 — Temporal fact store

**Story:** As a reviewer, I need rule versions, effective dates, expiry, and
supersession so checks use the right source for the publish date.

**Acceptance:** Store immutable rule versions; retrieve by channel and date;
expired/superseded sources are not treated as active; ambiguous overlapping
sources escalate.

### F3 — Channel-aware context

**Story:** As a creator, I need checks against rules applicable to my channel.

**Acceptance:** Submit a channel; only matching active rules are supplied to
checks; the receipt lists the rule IDs and versions used.

### F4 — Deterministic check core

**Story:** As a reviewer, I need reproducible checks for facts and visuals.

**Acceptance:** Cover price, restricted terms, casing, asset fingerprint, text
contrast, and alt text; calculations are reproducible without an LLM; a finding
includes the relevant evidence and result.

### F5 — Scoped LLM checks

**Story:** As a creator, I need tone and claim suggestions without treating
generated output as truth.

**Acceptance:** Limit model checks to tone/messaging and claims; request strict
JSON; reject invalid output; validate each field against the shared contract;
record a processing receipt.

### F6 — Source verifier and abstention

**Story:** As a reviewer, I need every surfaced finding to be grounded in an
active source.

**Acceptance:** Drop invented rule IDs; drop paraphrased/non-matching quotes;
escalate expired rules; abstain on conflicting active rules; emit only
verified findings. Meet the 10 grounding / 10 conflict case pass bars.

### F7 — Review studio

**Story:** As a creator/reviewer, I need evidence, rewrites, disputes, and
history in one review flow.

**Acceptance:** Highlight character ranges; show rule version/source/quote,
status, and action; support accept/edit/dispute with a reason; retain version
history; present abstentions and escalation clearly.

### F8 — Hash-bound approval and void-on-edit

**Story:** As a reviewer, I need approval to apply only to the exact version I
reviewed.

**Acceptance:** Hash canonical text, channel, and sorted asset fingerprints;
reject creator self-approval; any later edit voids the prior approval and writes
the diff to the audit log. Pass all five edit-void golden cases.

### F11 — AI processing receipt

**Story:** As a user, I need to know what the AI run received and the applicable
redaction/retention terms.

**Acceptance:** A receipt is created for every run and records sent text, exact
active rule versions, redaction, provider/retention terms, and timestamp.

## Round 3 — Deferred

### F9 — Governance insights

Aggregate repeated override friction by rule and channel into guideline-clarity
tickets. Require written override reasons. Pass all five seeded friction cases
with zero automatic rule rewrites.

### F10 — One-click audit export

Provide an authorized export of the append-only audit trail. Define export
format, access policy, and privacy review before implementation.

## Deliberately out of scope

Video/multi-page documents, multi-language rule sets, CMS/social publishing
hooks, and automatic publishing are not MVP tickets. Any change requires a
scope decision and updated golden cases.
