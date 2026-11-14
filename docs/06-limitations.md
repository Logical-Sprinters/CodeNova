# 06 · Limitations

What this build does not do, why, and what closing each gap would cost. Written before
anyone else asks, because a reviewer's first question should not be a surprise.

## Honesty markers

- **0 customer interviews, 0 pilot users, 0 scored evaluation cases.** This is a working
  prototype, not a validated product. Anything that looks like traction is a seed fixture.
- **No compliance certification of any kind.** No SOC 2, no ISO 27001, no GDPR
  attestation. The UI does not display badges, because displaying one would be a lie.
- **Some numbers shown by generated UI prototypes in earlier design drafts were invented.**
  They were deleted; anything on screen now comes from an API field or is not shown.

## Authentication and authorisation

| What | Reality |
|---|---|
| Authentication | none — `X-User-Id` header, no password, no token, no session |
| Authorisation | real, in two places: the API checks the role, and the approval trigger re-checks role, `is_active`, author and hash |
| Multi-tenancy | none. One organisation, no `tenant_id`, no row-level security |
| User management | none. Users exist only as seed rows |

**Cost to close:** a real identity provider (OIDC), sessions, and an admin surface. Days,
not hours — and it changes the schema (tenant column + RLS policies on every table).

## The checker

- **Deterministic phrase and price matching only.** It will miss copy phrased unusually, and
  it cannot judge tone, sarcasm, or implication.
- **Covers four rule families** (price, naming, absolute claims, terminology). `VISU-*`
  rules exist in the guidelines screen and are **not evaluated** — no image analysis.
- **No LLM path.** Deliberate: a model can invent a rule, and one invented rule in a
  governance product is worse than no product. The roadmap keeps an LLM behind the same
  citation contract, never in place of it.
- **No retrieval over long documents.** Rules are hand-authored rows with a source page.
  There is no ingestion, no OCR, no PDF parsing, no embeddings (`pgvector` is not installed).
- **Span offsets are Python code points.** For ASCII they equal Dart's UTF-16 offsets; with
  emoji or non-BMP characters, highlights would drift.
- **Overlapping findings are suppressed.** One finding per overlapping region, so a phrase
  that breaks two rules reports once.

## The approval model

- **Approvals are not append-only.** Each approval is *bound* to one immutable version by
  hash; a new version voids it, and the void is written to an append-only log. The README
  states it that way, and so should any slide.
- **No signature, no certificate.** The hash proves the text did not change; it does not
  prove who approved it beyond the header identity.
- **Approval is per content version, not per channel or locale.** One version, one approval.

## Data and operations

- **No migrations framework.** Three numbered files, applied in order. Fine at this size,
  wrong at the next one.
- **No backups, no replication, no monitoring.** One container, one volume.
- **No pagination.** The ledger is capped at 200 rows; lists are not paged.
- **No soft deletes.** Deleting a content item cascades to its versions and findings.
- **No rate limiting.** CORS is open for the Flutter web build, which is a prototype
  concession and says so in `backend/app/main.py`.

## The client

- **Two form factors, not two products.** The layout switches at 720 px; there is no
  tablet-specific design, no offline mode, no push notifications.
- **One dependency (`http`).** No state-management package, no code generation, no router
  package — deliberate, and the reason the whole app analyses clean on a fresh clone.
- **No accessibility audit.** Tap targets are 52 px and contrast is checked by eye, not by
  a tool. That is a claim to verify, not a claim to make.
- **No localisation.** English, one locale, hard-coded strings.

## What would be built next, in order

1. Real authentication (OIDC) and a tenant column with RLS.
2. LLM checks behind the same citation contract, with the deterministic checks as the
   blocking layer and the model as advisory only.
3. PDF/markdown ingestion into `guideline_documents` → `rules`, with the page number
   preserved, so a brand team can onboard its own guidelines without hand-writing rows.
4. A rule-change impact view: when a guideline changes, which live approvals cited it.
5. The clarity-ticket loop closing back into rule editing — today it reports, it does not
   propose.
