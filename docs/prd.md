# Product Requirements Document

**Status:** Requirements baseline from the Round 1 submission. This document
describes the intended product; it does not claim that the features are built.

## Product summary

BrandGuard is a pre-publication brand-governance tool. It checks marketing
content against approved, versioned brand rules and keeps an evidence ledger of
findings, human decisions, approvals, and later edits.

Product promise: **no finding without evidence, no approval without a version,
and no override without learning.**

## Problem

Brand rules often live in static documents while content is produced by
employees, agencies, and AI tools across channels. Manual review can miss
retired facts, unsupported claims, visual problems, and inconsistent
terminology. Decisions are difficult to repeat or audit when findings do not
cite the rule and version behind them.

The submission identifies three recurring properties: problems are silent,
recurring, and untraceable. BrandGuard is intended to make checks actionable
and decisions inspectable, not to replace human judgment with a score.

## Users

| User | Need |
| --- | --- |
| Creator / agency copywriter | Understand the exact rule and evidence, fix or dispute a finding, and retain control of the draft. |
| Brand or marketing manager | Review a queue and see repeated friction across rules, agencies, and channels. |
| Authorised reviewer (including legal/compliance) | Verify high-risk claims and approve the exact content version. |
| Admin / guideline owner | Ingest source material, confirm and version proposed rules, resolve conflicts, and clarify guidance. |

The first authorization model has `admin`, `creator`, and `reviewer` roles.
Manager is a product stakeholder, not a separate system role in the current
requirements.

## Goals and success measures

### Product goals

1. Ground every displayed finding in an active, versioned source rule and an
   exact evidence quote.
2. Abstain and escalate rather than guess when evidence is expired, conflicting,
   or insufficient.
3. Bind approval to the exact content, channel, and asset fingerprints; edits
   after approval invalidate it.
4. Make every override explainable and every AI run visible through a processing
   receipt.

### Research status and impact targets

The Round 1 submission reports research as **in progress**, with zero completed
at that time. The figures below are targets, not measured results.

| Measure | Target |
| --- | ---: |
| Interviews | 10 |
| Drafts audited | 40 |
| Review threads observed | 8 |
| Verbatim quotes with consent | 10 |
| Review turnaround | 50% reduction in a four-week pilot |
| Revision rounds per approved asset | 40% reduction |
| Post-approval drift | 0 exports with a hash different from the approved hash |
| Unsupported claims published | 0 |

Do not present targets as achieved results. Update the research log only with
measured, consent-compliant data.

## Product workflow

1. **Ingest:** an admin supplies guidelines, fact sheets, and approved assets.
   The system proposes rules; an admin confirms and versions them.
2. **Submit:** a creator provides draft text, a static image, channel, and
   intended publish date.
3. **Check:** deterministic checks run first; a scoped language model may check
   tone and claims using strict structured output.
4. **Verify:** the verifier checks every candidate against active rule versions
   and evidence. Invalid candidates are dropped; expiry or conflict causes
   abstention and escalation.
5. **Review:** the creator fixes, edits, or disputes findings with a reason. An
   authorised reviewer approves the exact version.
6. **Learn:** repeated overrides may create guideline-clarity tickets. Rules
   are never rewritten automatically.

## Functional requirements

- **FR-01 Rule ingestion:** accept the supported guideline inputs, propose
  structured rules, and require admin confirmation before activation.
- **FR-02 Rule versioning:** retain source, type, version, status, effective
  date, expiry, supersession, risk tier, and applicable channels.
- **FR-03 Channel context:** retrieve only rules applicable to the submission's
  channel.
- **FR-04 Deterministic checks:** support the MVP checks for price, terminology,
  casing, asset fingerprint, contrast, and alt text.
- **FR-05 Scoped AI checks:** use the model only for tone and claims, validate
  strict JSON output, and never treat model confidence as proof.
- **FR-06 Source verification:** apply the five verifier gates defined in the
  technical requirements. No unverified finding is shown to a human.
- **FR-07 Review studio:** show evidence, character-range highlights, suggested
  rewrites, statuses, review history, and dispute/override actions.
- **FR-08 Hash-bound approval:** store an approval for a canonical content
  version; any edit to text, channel, or assets voids the prior approval.
- **FR-09 Governance insights (deferred):** aggregate override friction into
  guideline-clarity tickets without rewriting rules.
- **FR-10 Audit export (deferred):** provide a one-click audit export.
- **FR-11 Processing receipt:** create a receipt for every AI run, recording
  sent content, active rule versions, redaction, provider/retention terms, and
  time.

## Finding statuses

| Status | Meaning | Expected action |
| --- | --- | --- |
| Confirmed rule match | Exact contradiction of an active approved source | Block export until resolved or an exception is recorded. |
| AI interpretation | Tone or messaging judgment | Advisory; reviewer confirms or clears it. |
| Unsupported | No approved evidence supports or disproves the claim | Flag for review; do not call it false. |
| Source conflict or expired | Active sources disagree or the cited rule has expired | Abstain and escalate to an admin. |
| Needs authorised reviewer | High-risk or regulated claim | Route to the authorised reviewer. |

## MVP scope and non-goals

The Round 2 judged MVP is F1-F8 and F11. F9 governance insights and F10 audit
export are deferred to Round 3.

The first release deliberately excludes video and multi-page documents,
multi-language rule sets, CMS/social publishing hooks, and auto-publishing.
Static-image checks are not a full accessibility audit.

## Acceptance principles

- An invented rule ID or paraphrased evidence quote never reaches a reviewer.
- Expired or conflicting sources cause escalation/abstention, not a guessed
  answer.
- A creator cannot approve their own submission.
- Any post-approval content edit voids the previous approval and is recorded.
- Every override has a written reason; every AI run has a processing receipt.
- Public demos use fictional TaskFlow data only.
