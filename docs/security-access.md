# Security and Access Requirements

**Status:** Design requirements only. The current scaffold does not implement
authentication, authorization middleware, upload handling, or production
retention controls.

## Roles and permissions

| Role | Allowed responsibilities | Restrictions |
| --- | --- | --- |
| Admin | Propose/confirm/version rules; resolve source conflicts and expiry; manage guideline clarity. | Cannot silently change historical rule or audit evidence. |
| Creator | Create and edit own drafts; run checks; accept, dismiss, or dispute findings with reasons. | Cannot approve own content or alter audit records. |
| Reviewer | Review evidence and approve a content version; handle high-risk review where authorized. | Cannot approve the creator's own version. |

Use deny-by-default authorization and check both role and object ownership on
every API operation. The brand/marketing manager is a product stakeholder, not
a defined authorization role yet. Do not grant permissions based on UI hiding
alone.

## Required controls

- Keep credentials and provider keys in environment configuration; commit only
  `.env.example`.
- Validate every request and model response against shared Pydantic/JSON Schema
  contracts.
- Enforce upload type and size limits and re-encode images before inspection.
  Exact limits and supported formats remain an implementation decision.
- Treat draft text and uploaded files as untrusted, including prompt-injection
  attempts. Model output never grants authority or bypasses verification.
- Send only the draft and active rules relevant to its channel. Record the
  sent text/rule versions, redactions, and retention terms in a receipt.
- Retain no uploaded client artwork after checking; retain only required
  content text/version history, hashes/fingerprints, findings, receipts, and
  audit evidence under an approved retention policy.
- Make the audit log append-only and require a written reason for overrides.
- Enforce no self-approval server-side and bind approval to the exact version
  hash.
- Apply rate limits and a spend cap to model calls; scan dependencies before
  release.
- Do not use real client material in public demos; TaskFlow is fictional.

## Data handling

Draft text, source rules, findings, processing receipts, and audit entries may
contain sensitive business information. Restrict access to users with a
project-appropriate role. The exact retention duration, deletion workflow,
encryption/key-management approach, identity provider, and incident contact
remain open decisions and must be documented before a pilot.

## Reporting

Report suspected vulnerabilities privately to the maintainers, not in public
issues. A monitored security contact must be configured before production use.
