# BrandGuard AI / Teammate Handoff

Read this after cloning to understand what code is real, how to run it, and where work should continue.

## Repo and active paths

- Repository: `Logical-Sprinters/CodeNova`; branch context: `omkar`.
- Local project folder used during development: `BrandGuard-App`.
- Active client for the recent API integration: `mobile/brandguard/`.
- FastAPI backend: `backend/`.
- There is a separate Flutter project under `frontend/`; do not conflate its routes/config with `mobile/brandguard/`.

## Run on Windows PowerShell

Terminal A:

```powershell
cd BrandGuard-App\backend
python -m pip install fastapi uvicorn
python -m uvicorn app.main:app --reload
```

Terminal B:

```powershell
cd BrandGuard-App\mobile\brandguard
flutter pub get
flutter run -d chrome
```

API root `http://127.0.0.1:8000/`; health `/health`; Swagger `/docs`. Flutter Web API base URL is hardcoded in `lib/services/brandguard_api_service.dart`. Android emulator commonly uses `10.0.2.2`; physical device requires a LAN IP.

## Actual request flow

1. Flutter sends `brand_name`, `content`, `content_type: text` to `POST /api/v1/brand/check`. Client currently sends sample brand key `acme`.
2. FastAPI combines base deterministic regex checks with rules from `backend/app/rules_store/brand_rules.json`.
3. If findings exist, JSON review record status becomes `pending`; no findings yields `completed`. API response status is `review_required` or `completed`.
4. The API generates a UUID check ID, SHA-256 hash of submitted text, and processing receipt.
5. Flutter displays returned findings in Findings & Evidence.
6. Review Queue fetches records through `GET /api/v1/reviews`.
7. Review decisions go through `PATCH /api/v1/reviews/{check_id}/decision`; API accepts only `approved` or `rejected`. Request Changes is translated to rejected with a note.
8. `POST /api/v1/approvals/verify` checks approved state, check ID, brand, text hash, and current rules version.

## Backend file map

| Path | Role |
|---|---|
| `backend/app/main.py` | FastAPI, routers, CORS, root/health |
| `backend/app/schemas/brand.py` | Request/response models |
| `backend/app/checks/deterministic/engine.py` | Base regex checks + brand rules |
| `backend/app/rules_store/brand_rules.json` | Fictional Acme rules |
| `backend/app/rules_store/store.py` | Load versions/rules |
| `backend/app/approval/store.py` | JSON records, SHA-256, decisions, verify |
| `backend/app/routers/brand.py` | Brand check and rule lookup |
| `backend/app/routers/reviews.py` | Review list/decision/verify |
| `backend/app/receipts/store.py` | Receipt JSON persistence |
| `backend/app/routers/receipts.py` | Receipt list/detail |
| `backend/app/checks/llm/verifier.py` | Abstention stub, not a live LLM |

## Flutter file map

| Path | Role |
|---|---|
| `mobile/brandguard/lib/services/brandguard_api_service.dart` | API calls |
| `mobile/brandguard/lib/screens/workspace/new_brand_check_screen.dart` | Check submission |
| `mobile/brandguard/lib/screens/workspace/findings_evidence_screen.dart` | Backend findings display; demo actions remain |
| `mobile/brandguard/lib/screens/review/review_queue_screen.dart` | Backend queue and decisions; legacy helpers remain |

## Sample rules

- `BG-001`: unfinished placeholder (lorem ipsum, TODO, insert placeholder).
- `BG-002`: selected absolute claims (guaranteed, 100% safe/secure/effective, risk-free).
- Fictional Acme v1.0.0: `ACME-001` “free forever”; `ACME-002` “best in the world”.

These do not represent policy of a real brand.

## Limitations and caution

- JSON persistence: review records at `backend/app/approval/review_records.json`; receipts at `backend/app/receipts/receipts.json`. Local demo records may be present in the repository.
- JSON file storage is not production-safe for concurrent use.
- Hash currently covers submitted text only; target spec's canonical hash includes channel/assets but is not implemented.
- No auth/role checks; reviewer name is supplied in request. CORS is permissive for local development.
- AI verifier abstains without verified facts; no provider/retrieval is connected.
- Some client labels, suggestions, CTA and counts remain hardcoded or local.
- JSON Schemas in `packages/contracts/` are not generated into runtime Pydantic types.

## Continue from

Use [Implementation Status](IMPLEMENTATION_STATUS.md) as the task source. Preserve UI design, change one vertical slice at a time, and validate API behavior in Swagger plus Flutter in Chrome. Do not claim planned requirements as delivered.
