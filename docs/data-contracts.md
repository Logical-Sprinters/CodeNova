# Data Contracts

JSON Schema files in [`../packages/contracts/`](../packages/contracts/README.md)
are the intended single source of truth for Pydantic v2 and TypeScript types.
Code generation is not configured yet; do not hand-maintain diverging API
shapes.

| Contract | Schema |
| --- | --- |
| Rule | [`rule.schema.json`](../packages/contracts/rule.schema.json) |
| Finding | [`finding.schema.json`](../packages/contracts/finding.schema.json) |
| Approval record | [`approval.schema.json`](../packages/contracts/approval.schema.json) |
| Audit entry | [`audit-entry.schema.json`](../packages/contracts/audit-entry.schema.json) |
| Processing receipt | [`processing-receipt.schema.json`](../packages/contracts/processing-receipt.schema.json) |

## Contract invariants

- A rule is identified by its rule ID and version and includes source, status,
  dates, channels, risk tier, and supersession metadata.
- A finding references a specific rule version and exact evidence quote.
  Character spans use zero-based start and exclusive end offsets.
- An approval is bound to an immutable content version and its canonical
  lowercase SHA-256 hash.
- User actions and system actions are distinguishable in the audit record;
  override reasons are required.
- A processing receipt lists the text and exact rule versions sent, redactions,
  provider, retention terms, and creation time.
- JSON Schema validates shape, not authorization or truth. The API must still
  verify the rule is active/applicable, enforce the verifier gates, and apply
  state-transition and access-control rules.

Canonical hash input is stable JSON containing text, channel, and sorted asset
fingerprints after whitespace and Unicode normalization. Never hash an
unordered or mutable representation.
