# Implementation Plan

This file tracks the current implementation work. The original three-round scope remains a planning baseline; see [Feature Tickets](feature-tickets.md) for feature status.

## Current development phase — local end-to-end prototype

**Implemented**
- FastAPI app and local CORS.
- Deterministic rule engine and JSON sample brand rules.
- Brand check endpoint and response schemas.
- JSON persistence for review/check records.
- Review decision API with approved/rejected states.
- Content SHA-256 and approval verification endpoint.
- Processing receipt creation and list/detail API.
- Flutter API service in `mobile/brandguard`.
- Flutter New Brand Check and Findings & Evidence use backend results.
- Flutter Review Queue loads backend records and decision API integration is present.

**In progress / needs validation**
- End-to-end test approve, reject, and Request Changes from Flutter and Swagger.
- Replace Findings & Evidence local submission behavior with truthful UI tied to existing check ID.
- Show receipt details in Flutter.
- Build visible approval verification workflow and prove edited text fails.
- Remove or label hardcoded demo context, suggestion counts, sample records and legacy local helpers.
- Add repeatable tests and pinned dependency manifests.

## Suggested next sequence

1. Confirm reviewer, note, decision and timestamp persist for approve/reject.
2. Request Changes should have a distinct backend status if needed; it currently maps to rejected with a note.
3. Use `GET /api/v1/receipts/{receipt_id}` and display receipt ID, check ID, rule version, engine, finding count, AI abstention and final status.
4. Remove local duplicate queue submission; backend creates the pending review at check time.
5. Polish honest UI states and remove hardcoded counts.
6. Add API tests and Flutter widget/manual acceptance coverage.
7. Add pinned backend dependencies and clean-clone setup.
8. Consider trusted facts and a real LLM provider only after source grounding/privacy design.

## Original planned rounds

- Round 1: plan/research/contracts/golden cases.
- Round 2: intended F1-F8 and F11; current code is a smaller vertical slice and does not meet all ticket acceptance scope.
- Round 3: F9 governance insights and F10 audit export deferred; pilot/security readiness also remains.

Do not claim the original Round 2 exit criteria have been met merely because the vertical slice runs.
