# Data Contracts

Define shared JSON schemas in `packages/contracts` and use them to generate
Pydantic models and TypeScript types.

Core records:

- **Rule:** identifier and version, type, text, source, status, effective and
  expiry dates, superseded rule, risk tier, channels, and confirming admin.
- **Finding:** status, referenced rule version, evidence quote, optional text
  span, message, suggested fix, and system action.
- **Approval:** content version, lifecycle state, canonical SHA-256 hash,
  reviewer, approval time, and void details.
- **Audit entry:** content, actor, action, reason when overridden, and timestamp.

Canonical hashes use normalized content and sorted asset fingerprints. Every
finding must be grounded in an active rule version and evidence quote.
