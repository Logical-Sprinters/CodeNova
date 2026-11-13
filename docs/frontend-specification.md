# Frontend Specification (UI/UX)

**Status:** Interaction specification; the web application is not implemented.

## Design principles

- Make findings actionable and attributable: show the exact rule version,
  source, quote, status, and system action.
- Preserve the creator's control of wording. Suggested rewrites are proposals;
  never silently replace the submitted draft.
- Make uncertainty visible. Use "unsupported", "conflict", "expired", and
  "needs authorised reviewer" rather than a confidence score or a false/true
  judgment.
- Keep review state and version/hash visible. An edit after approval must show
  that the old approval is void.

## Routes and primary users

| Route | Primary user | Purpose |
| --- | --- | --- |
| `/submit` | Creator | Enter text, upload a static image, select channel and publish date, then run checks. |
| `/review` | Creator and reviewer | Inspect findings, evidence spans, fixes, disputes, history, and approval state. |
| `/rules` | Admin | Review proposed rules, source references, versions, dates, channels, and conflicts. |
| `/audit` | Admin/reviewer | Inspect append-only decisions and processing receipts. |

## Screen requirements

### Submit

- Provide fields for draft text, channel, publish date, and static image input.
- Explain supported formats/limits before upload; those values must come from
  the eventual backend configuration.
- Show check progress and distinguish deterministic from AI-assisted checks.
- Never display "approved" merely because a check completed.

### Review studio

- Use TipTap to highlight exact character ranges associated with findings.
- Show an evidence card for each finding: status, rule ID/version, source
  reference, exact quote, explanation, suggested fix, and system action.
- Support edit, accept/dismiss, and dispute actions. Require a reason for an
  override; show that it was recorded.
- Keep the creator's original text and edits recoverable in version history.
- Show the canonical hash and reviewer identity/time after approval.
- When text, channel, or asset changes after approval, show `VOID`, the changed
  fields/diff, and the path back to review.

### Rules administration

- Separate draft proposals from active rules.
- Require admin confirmation before activation.
- Show source file/page, version, channel, effective/expiry dates, supersession,
  and risk tier together.
- Surface overlapping/conflicting sources as a conflict requiring resolution,
  not as an automatic winner.

### Receipt and audit

- Show what draft text and active rule versions were sent, what was redacted,
  applicable retention terms, and the run timestamp.
- Keep audit events chronological and distinguish user actions from system
  actions.

## Status and interaction treatment

The five product statuses are confirmed rule match, AI interpretation,
unsupported, source conflict/expired, and needs authorised reviewer. Pair every
status label with text and an explicit next action; do not rely on color alone.

## Accessibility and responsive behavior

- Meet WCAG AA contrast for normal text (4.50:1); show contrast measurements
  when a deterministic visual check flags an issue.
- Provide keyboard-accessible editor controls, focus indicators, semantic
  headings, and screen-reader labels for status and evidence.
- Ensure a finding can be understood without color or a hover interaction.
- Contrast and alt-text checks do not constitute a complete WCAG audit.
- Validate the editor, evidence cards, and review flow at desktop and narrow
  viewport widths before pilot.

## Not specified yet

The submission does not define brand colors, typography, spacing tokens,
responsive breakpoints, exact upload limits, or final component designs. Agree
these in design review rather than inventing project-wide design tokens here.
