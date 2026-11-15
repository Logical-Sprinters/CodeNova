# BrandGuard Flutter Client — `mobile/brandguard`

This is the Flutter client currently used for BrandGuard's FastAPI integration. It runs in Chrome for the local prototype; it is not yet a production mobile app.

## Connected features

- **New Brand Check:** posts text to `POST /api/v1/brand/check` (sample brand key currently `acme`).
- **Findings & Evidence:** renders returned finding IDs, severity, messages and evidence.
- **Review Queue:** fetches backend reviews and calls backend approve/reject endpoint.
- **Approval verification:** API client method exists; complete user-facing workflow remains to be finished.
- **Processing receipts:** receipt ID is passed through; details are not fully presented in Flutter yet.

Some demo labels, local suggestion state and legacy review helpers remain. Refer to [Implementation Status](../../../docs/IMPLEMENTATION_STATUS.md) before assuming a visible control is fully backend-backed.

## Run

Start backend in another terminal:

```powershell
cd backend
python -m pip install fastapi uvicorn
python -m uvicorn app.main:app --reload
```

Then run Flutter:

```powershell
cd mobile/brandguard
flutter pub get
flutter analyze
flutter run -d chrome
```

Flutter Web currently uses `http://127.0.0.1:8000` from `lib/services/brandguard_api_service.dart`. Android emulator/physical device networking requires a different host.

## Main code paths

- `lib/services/brandguard_api_service.dart` — API client
- `lib/screens/workspace/new_brand_check_screen.dart` — check submission
- `lib/screens/workspace/findings_evidence_screen.dart` — result display/demo actions
- `lib/screens/review/review_queue_screen.dart` — queue and decision actions
