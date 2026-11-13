# Threat Model

**Status:** Initial threat inventory for the proposed MVP; validate it with the
implemented deployment before pilot.

## Assets and trust boundaries

| Asset | Sensitivity / integrity need |
| --- | --- |
| Draft text, uploaded static images, and publish context | Potentially confidential client material; process only what is needed and do not retain artwork after checking. |
| Source documents and rule versions | Integrity-critical; changes must be admin-confirmed, versioned, and traceable. |
| Findings and evidence quotes | Must be grounded in the cited rule version and draft span. |
| Approval hash and state | Must identify the exact text, channel, and asset fingerprints reviewed. |
| Credentials and model API keys | Secret; keep out of source control and logs. |
| Processing receipts and audit history | Sensitive and integrity-critical; access-controlled and append-only. |

Trust boundaries include the browser/API boundary, uploaded files/API parsing,
API/database, and API/model provider. Draft text and model output are untrusted
at every boundary.

## Threats and mitigations

| Threat | Impact | Required mitigation |
| --- | --- | --- |
| Prompt injection in draft text | Model ignores rules or emits manipulated findings | Treat draft as data, send only relevant rules, validate strict JSON, and run every candidate through the verifier. Add a prompt-injection golden test. |
| Hallucinated rule ID or paraphrased quote | Unsupported finding reaches a human | Drop at verifier gates 1 or 2; no evidence means no finding. |
| Expired or conflicting source | Wrong fact is approved | Check effective/expiry/supersession; abstain and escalate on conflict. |
| Creator self-approval | Unreviewed content appears approved | Enforce role and creator/reviewer separation on the server and in the database. |
| Edit after approval | Published content differs from signed version | Canonical SHA-256 hash, immutable versions, automatic VOID, diff, and audit entry. |
| Malicious or oversized upload | Parser/image library abuse or resource exhaustion | Allowlist types, enforce size limits, re-encode images, isolate parsers, and retain no uploaded art after checking. |
| API key exposure or model-cost abuse | Data disclosure or unexpected cost | Environment-only secrets, rate limits, spend cap, secret scanning, and dependency scanning. |
| Audit alteration | Loss of accountability | Append-only database behavior; application role cannot update/delete/truncate audit data. |
| Sensitive receipt leakage | Exposure of draft or rule content | Restrict access, redact where required, record retention terms, minimize logs, and set a reviewed retention/deletion policy. |
| Contrast/visual false assurance | Accessibility defect ships | Label checks narrowly; report contrast/alt-text results without claiming a complete WCAG audit. |

## Residual risks and release blockers

- Authentication provider, encryption/key management, exact upload limits, data
  retention duration, deletion workflow, and incident contact are not yet
  selected.
- PostgreSQL roles/privileges, network segmentation, backups, monitoring, and
  deployment secrets must be reviewed in the actual deployment.
- AI output can still be incomplete; the product must preserve abstention and
  human review rather than promise truth detection.
- Do not begin a real-client pilot until these decisions, a security review, and
  consent procedures are complete.
