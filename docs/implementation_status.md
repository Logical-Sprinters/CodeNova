# BrandGuard Implementation Status

**Last updated:** 15 November 2026  
**Branch context:** `omkar`  
Update this document when implementation changes. Distinguish partial prototype slices from complete acceptance criteria.

## Summary

A local vertical slice exists: FastAPI performs deterministic text checks, persists JSON review records and receipts, and Flutter Web calls the API for checks and review-queue decisions. It is not a production system.

## Implemented

### Backend
- FastAPI app, root/health, local CORS.
- Request/response schemas for checks, findings, review decisions, and approval verification.
- Deterministic base rules: placeholder text (lorem ipsum/TODO/insert placeholder) and selected unsupported absolute claims.
- Fictional Acme rules from `backend/app/rules_store/brand_rules.json`: `ACME-001` restricted phrase “free forever”; `ACME-002` superlative “best in the world”; current version 1.0.0.
- Brand check creates UUID, computes SHA-256 over content, stores record, creates processing receipt, returns findings.
- JSON-backed review record storage and receipt storage.
- Review listing and approve/reject decision API.
- Approval verification checks status, check ID, brand name, content hash, and current rules version.
- Receipt list and detail endpoints.
- AI verifier explicitly abstains if verified brand facts are absent.

### Flutter (`mobile/brandguard`)
- Flutter Web runs in Chrome.
- API service provides check, reviews, decision, and approval-verify methods.
- New Brand Check sends content to FastAPI.
- Findings & Evidence renders backend rule IDs, severity, messages, and matched evidence.
- Review Queue loads backend records and calls decision endpoints.
- Approve/reject actions are connected. Request Changes maps to backend rejected status with a prefixed reason note.
- `flutter analyze` was reported with no issues in the mobile project after the recent review-queue changes.

## Partial / needs end-to-end validation
- Findings screen retains demo context, local suggestion/rewrite logic and some static UI text.
- Submit-for-review CTA still creates a local mock submission through a legacy helper; backend already creates the pending review record at check time, so this can cause a confusing/duplicate local-only representation.
- Receipt ID is passed into Findings screen, but receipt details are not fully shown in Flutter.
- Approval verification client method exists; a clear screen-level workflow and exact-content-vs-edited-content demonstration remain.
- Review Queue contains legacy local/demo helper structures although the displayed queue is fetched from backend.
- Request Changes is not a first-class backend status.
- Integration behavior should be tested from Flutter and Swagger, not inferred from successful analysis.

## Not implemented — do not claim as delivered
- Live LLM provider, verified-fact retrieval, grounded AI findings.
- Five-gate source verifier.
- Guideline ingestion/admin confirmation, temporal applicability, channel filtering, source-conflict resolution.
- PostgreSQL runtime, migrations, or production persistence.
- Authentication, server-enforced role/ownership permissions, creator/reviewer separation.
- Append-only production audit trail.
- Image uploads or visual checks.
- Canonical hash of text + channel + asset fingerprints, immutable content versions, void-on-edit/diff lifecycle.
- F9 governance insights, F10 audit export, production deployment/monitoring.

## Implemented API endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | Root/status |
| GET | `/health` | Health |
| POST | `/api/v1/brand/check` | Deterministic check; create record and receipt |
| GET | `/api/v1/brand/rules/{brand_name}` | Current/available brand rule versions |
| GET | `/api/v1/reviews?status=pending` | List reviews; status filter optional |
| PATCH | `/api/v1/reviews/{check_id}/decision` | Record approved/rejected |
| POST | `/api/v1/approvals/verify` | Check approval integrity |
| GET | `/api/v1/receipts/` | List receipts |
| GET | `/api/v1/receipts/{receipt_id}` | Retrieve one receipt |

## Next work in suggested order

1. End-to-end verify approve, reject, Request Changes; confirm reviewer/note/time in API.
2. Replace Findings screen's local submission helper with truthful state tied to the existing check ID.
3. Display receipt details in Flutter.
4. Wire approval verification into UI and show exact approved text succeeds / edited text fails.
5. Remove or clearly label stale mock content, counts, and helper data.
6. Add backend tests, Flutter widget/manual tests, and a pinned backend dependency file.
7. Only then evaluate trusted facts and real LLM integration.
