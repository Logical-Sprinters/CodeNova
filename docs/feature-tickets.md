# Feature Ticket Backlog and Status

Status reflects code in this branch. **Partial** means a prototype slice exists, not that the ticket's full acceptance criteria are satisfied.

| Ticket | Feature | Current status |
|---|---|---|
| F1 | Rule ingestion and admin confirmation | Not implemented; JSON sample rules loaded directly |
| F2 | Temporal fact store | Partial foundation only; rule version field exists, no date/channel applicability |
| F3 | Channel-aware context | Not implemented |
| F4 | Deterministic check core | Partial; regex text checks exist, not the full price/terminology/casing/visual scope |
| F5 | Scoped LLM checks | Stub/abstention only; no live provider |
| F6 | Source verifier and abstention | Abstention stub exists; five verifier gates not implemented |
| F7 | Review studio | Partial; backend findings and review queue shown, full history/dispute/editor flow not done |
| F8 | Hash-bound approval and void-on-edit | Partial; text SHA-256 and verify endpoint exist; canonical text/channel/assets, void lifecycle, diff/audit not implemented |
| F9 | Governance insights | Deferred |
| F10 | One-click audit export | Deferred |
| F11 | AI processing receipt | Partial; receipt creation and API retrieval exist, full metadata and Flutter presentation incomplete |

## MVP follow-up checklist

- [ ] Verify decisions from Flutter and inspect reviewer/note/time persistence.
- [ ] Add distinct Request Changes status if required; currently mapped to rejected with a note.
- [ ] Confirm exact approved text verifies and modified text fails.
- [ ] Confirm rule-version mismatch invalidates approval.
- [ ] Remove duplicate local review submission from Findings & Evidence.
- [ ] Show receipt details in Flutter.
- [ ] Document clean-clone setup and dependency versions.
- [ ] Add automated backend and Flutter tests.
- [ ] Remove or visibly label demo-only text/counts.

The full original F1-F11 acceptance scope remains the product baseline; it must not be represented as delivered unless the status above is updated.
