# Contributing

Thank you for helping build BrandGuard. Open an issue before substantial work
so the team can agree on the problem, acceptance criteria, and whether it fits
the current round's scope.

## Product principles

Use the product's design rule: **deterministic first, model second, proof last**.

- AI proposes; an authorised human approves. The system must never auto-publish
  or treat an AI confidence score as proof.
- Every finding must cite an active, versioned rule and an exact supporting
  quote. Drop invented rule IDs and paraphrased quotes.
- Abstain and escalate expired rules or conflicting active sources. Treat
  missing evidence as unsupported, not false. Route high-risk claims to an
  authorised reviewer.
- Bind approval to the canonical SHA-256 hash of the text, channel, and sorted
  asset fingerprints. Any edit after approval must void that approval.
- Record a processing receipt for every AI run. Overrides need a written reason;
  they may inform guideline-clarity tickets but must never rewrite rules
  automatically.
- Keep uploaded client artwork out of the repository and do not retain it in
  research notes or demo data.

## Project scope

The judged Round 2 MVP is F1-F8 and F11:

1. Rule ingestion and admin confirmation.
2. Temporal rules with effective, expiry, and supersession data.
3. Channel-aware context.
4. Deterministic checks for prices, terms, casing, asset hashes, and contrast.
5. Scoped tone and claim checks using strict JSON.
6. Source verification and abstention.
7. Review studio with citations, rewrites, and history.
8. Hash-bound approval with void-on-edit.
9. An AI processing receipt for every run.

Governance insights from override telemetry (F9) and one-click audit export
(F10) are deferred. Video and multi-page documents, multi-language support,
CMS/social publishing hooks, and auto-publishing are deliberately out of scope.
Discuss a scope change in an issue before implementing it.

## Where to contribute

| Area | Expected changes |
| --- | --- |
| `frontend/` | Next.js review studio, TipTap editor, findings, and receipts. |
| `backend/` | FastAPI routes, Pydantic schemas, rule store, checks, verifier, approvals, audit, and receipts. |
| `packages/contracts/` | Shared schemas; update generated/API types and tests when a contract changes. |
| `tests/golden/` | Frozen grounding, conflict, edit-void, and friction cases. |
| `tests/e2e/` | End-to-end user workflows. |
| `research/` | Consent-based research materials and measured results only. |

Keep the API schemas and shared contracts aligned. Validate model output as
untrusted input; do not pass unvalidated dictionaries into approval or audit
flows.

## Development workflow

1. Create a focused issue with the user impact, acceptance criteria, and failure
   behavior.
2. Create a branch from `main`. Use names such as
   `feature/F6-verifier-gate-2`, `fix/approval-void`, or `docs/research-guide`.
3. Make the smallest change that satisfies the issue. Add or update tests for
   both the expected path and the relevant failure/abstention path.
4. Open a pull request against `main`, link the issue, summarize the behavior,
   and include test commands and results. Request at least one review; keep
   `main` demoable.

Use Conventional Commits, for example:

```text
feat(verifier): drop findings with paraphrased evidence
fix(approval): void approval after content edit
docs(contributing): explain golden test requirements
```

Common types are `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`,
`perf`, and `ci`.

## Tests and acceptance

The golden suite is intended to be frozen before implementation. Preserve these
acceptance bars when adding cases:

| Suite | Cases | Pass bar |
| --- | ---: | --- |
| Grounding | 10 | No ungrounded finding reaches a human. |
| Source conflict | 10 | Every conflict escalates; the system does not guess. |
| Edit-void | 5 | Every approved edit voids approval and records a complete log and diff. |
| Friction patterns | 5 | Every pattern becomes a ticket; no rule is rewritten automatically. |

Each golden case should include the input, active rules, expected findings, and
expected hidden content. Also cover invented rule IDs, paraphrased quotes,
expired sources, self-approval attempts, and the contrast example in the
submission.

For code changes:

- Run the relevant API, web, golden, and end-to-end checks; report the exact
  commands and results in the pull request.
- Test what users see when the system drops a finding, abstains, or escalates.
- Update contracts, documentation, and `.env.example` when the behavior or
  configuration changes.
- Keep research counts honest: targets are not results. Obtain written consent
  before interviews, record quotes only with permission, and leave unmeasured
  values blank.

This scaffold does not yet define runnable test commands. Add documented
commands when the corresponding test tooling is introduced rather than
reporting checks that were not run.

## Pull request checklist

- [ ] The change is within the agreed scope and linked to an issue.
- [ ] Relevant tests pass; new behavior and failure paths are covered.
- [ ] Shared contracts, docs, and configuration examples are updated as needed.
- [ ] No secrets, real client artwork, or unconsented personal information are included.
- [ ] The PR explains limitations and gives reproducible validation steps.
