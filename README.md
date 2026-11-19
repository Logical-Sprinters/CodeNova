# BrandGuard — Grounded, Time-Aware & Multimodal Brand Governance (v3.0.0 / Round 3)

**Tagline:** *No finding without evidence. No approval without a version.*

BrandGuard is a mobile-first brand governance platform where creators draft or upload marketing copy and campaign banners, a deterministic + grounded-AI policy engine evaluates exact content against time-scoped brand rules, and independent reviewers inspect evidence and issue cryptographically sealed approvals.

| | |
|---|---|
| **Hosted Web App** | https://brandguard-app.antideploy.app *(see [Deployment](#5-deployment--hosted-notes))* |
| **Client** | Flutter (`mobile/`) + prebuilt same-origin web bundle (`browser_preview/`) |
| **Backend** | FastAPI (`backend/`, Python **3.11+**, tested on **3.13**) |
| **Database & Auth** | Local SQLite + PBKDF2/JWT (local mode) · Supabase PostgreSQL + Auth + private Storage (cloud mode) |

---

## 1. What's New in Round 3 (v3.0.0)

### 3 Core Governance Improvements
1. **No Finding Without Evidence (Server-Side Grounding Gate)**
   - Every deterministic, visual, and AI finding requires an active `rule_id`, `rule_version`, a **verbatim `rule_quote`** + offsets from the stored `rule_text`, and an exact content/OCR span (`app/checks/grounding.py`).
   - Grounding is enforced **both** on check creation/resubmit and again on every reviewer/creator read (`GET /api/v1/reviews`, `GET /api/v1/receipts/{id}`, `GET /api/v1/history`). Ungrounded, paraphrased, or stale findings are **dropped** and logged in `audit_log` (`dropped_ungrounded_count`).
   - AI factual verification (`app/checks/llm/verifier.py`) operates strictly over **reviewer-verified Fact Sources** using strict JSON schema, verbatim source quote/hash/span checks, and explicit abstention (`abstained`) whenever disabled, unfunded, or lacking verified evidence.
2. **Correct Over Time (Temporal Rules & Point-in-Time Approval Verification)**
   - Rules and Fact Sources carry `effective_from`, `expires_at`, `supersedes`, `version`, `channel`, and `topic_key`.
   - `POST /api/v1/brand/check` and `/preflight` support `check_at` and `channel` to resolve the exact policy set active at that moment (`app/rules_store/store.py`).
   - `POST /api/v1/approvals/verify` and `/verify-upload` validate exact text/file SHA-256 hashes against stored approvals and report **specific rule changes** (`added_rules`, `removed_rules`, `changed_rules`) when rules evolve after sign-off.
3. **Multimodal Banner & Creative Inspector + OCR**
   - `POST /api/v1/files` accepts **`.png`, `.jpg`, `.jpeg`, `.webp`** images alongside `.txt`, `.md`, and text-based `.pdf` (up to 5 MB).
   - `app/checks/visual/inspector.py` extracts embedded banner text with **Tesseract OCR** (`tesseract-ocr` + `pytesseract`), fuses OCR text with caption copy (`source_origin: "image_ocr"`), checks dominant brand color palettes (`VIS-02`), checks deprecated/approved perceptual logo hashes (`VIS-05` + `POST /api/v1/library/rules/{rule_id}/logo-template`), and optionally runs Multimodal Vision AI when `AI_PROVIDER` is configured.

### 4 Product Differentiators
1. **Real-Time Inline Preflight Checks** — `POST /api/v1/brand/preflight` runs live checks while drafting in **New Brand Check** without writing noisy drafts/receipts/audit entries.
2. **Source-of-Truth Conflict Detection & Abstention** — `app/checks/conflicts.py` detects contradictions between active rules and verified facts sharing a `topic_key`, pauses the check (`abstained_conflict` / `paused_conflict`) instead of guessing, and lets reviewers resolve conflicts + optionally `auto_recheck` via `/api/v1/conflicts`.
3. **Coded Reviewer Overrides & Friction-Based Clarity Tickets** — Reviewers can override individual findings with 6 structured reason codes (`FALSE_POSITIVE`, `APPROVED_EXCEPTION`, `AMBIGUOUS_RULE_TEXT`, `OUTDATED_RULE_OR_FACT`, `CONTEXTUAL_QUALIFIER`, `CHANNEL_EXEMPTION`) via `/api/v1/reviews/{check_id}/findings/{finding_id}/override`. Overrides **never silently mutate rules**; repeated overrides roll up into **Clarity Tickets** (`/api/v1/clarity-tickets`) for rule owners.
4. **Cryptographic Tamper-Proof Receipt Diff & Full Profile Identity** — `ApprovalVerificationScreen` and `ReceiptDetailScreen` verify `receipt_hash` / chained integrity (`VALID` vs `VOIDED_TAMPERED`) and render inline word-level diffs between submitted and approved text. **Profile → My profile** displays full server-verified session & identity details (`Display name`, `Email`, `User id`, `Role`, `Auth provider`, `Database`, `Session state`) plus display-name editing backed by `PATCH /api/v1/auth/profile` and `GET/PUT /api/v1/auth/preferences`.

---

## 2. Quick Start (Local Development & Web Preview)

### Prerequisites
- **Python 3.11 or newer** (**Python 3.13 recommended** — `fastapi==0.163.1` and `SQLAlchemy==2.1.8` in `backend/requirements.txt` dropped Python 3.10 support).
- **Optional for local image OCR:** Install **Tesseract OCR** (`tesseract` on `PATH`, or `C:\Program Files\Tesseract-OCR\tesseract.exe` on Windows, or set `TESSERACT_CMD` in `backend/.env`). Note: `Dockerfile` installs `tesseract-ocr` automatically for container deployments.
- **Flutter 3.50.0 / Dart `^3.14.0`** (only required if modifying `mobile/` or rebuilding `browser_preview/`).

### A. Run the Full App Locally (FastAPI + Same-Origin Web UI)
`browser_preview/` contains a prebuilt web UI served at `http://127.0.0.1:8000/` alongside the API.

**macOS / Linux:**
```bash
python3 start_backend.py --web
```

**Windows (PowerShell):**
```powershell
cd path\to\CodeNova-smeet_final
py -3 start_backend.py --web
```
*(If `py` is not on PATH or your default `python` is 3.10, install Python 3.13 via `winget install -e --id Python.Python.3.13` and run using `& "$env:LocalAppData\Programs\Python\Python313\python.exe" start_backend.py --web`. Once `backend\.venv` exists, you can launch directly with:)*
```powershell
cd path\to\CodeNova-smeet_final\backend
.\.venv\Scripts\python.exe -m uvicorn app.web:app --host 0.0.0.0 --port 8000 --workers 1
```
Open **http://127.0.0.1:8000/** (`Ctrl+Shift+R` hard refresh after rebuilding the web bundle).

### B. Rebuild `browser_preview/` After Flutter Changes
```bash
cd mobile
flutter clean
flutter pub get --enforce-lockfile
flutter build web --no-web-resources-cdn
```
Then replace everything inside `browser_preview/` with the contents of `mobile/build/web/`:
```powershell
# PowerShell (from repo root)
Remove-Item browser_preview\* -Recurse -Force
Copy-Item mobile\build\web\* browser_preview\ -Recurse -Force
```

### C. Run the Flutter Mobile/Desktop App
Native builds default to `https://brandguard-app.antideploy.app`. Pass `API_BASE` explicitly for local development:
```bash
cd mobile
flutter pub get --enforce-lockfile

# Against local backend (Android emulator):
flutter run --dart-define=API_BASE=http://10.0.2.2:8000

# Against local backend (Windows/macOS/Chrome):
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000

# Against hosted backend:
flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
```

---

## 3. Authentication & Demo Credentials

### Local Mode (`AUTH_PROVIDER=local`, `SEED_DEMO_USERS=true` — default)
When running locally with `backend/.env` unset (or `SEED_DEMO_USERS=true`), two local demo accounts are seeded automatically and displayed in the Sign In **Local demonstration accounts** card:

| Role | Name | Email | Password | Capabilities |
|---|---|---|---|---|
| **Creator** | Alice | `creator@brandguard.demo` | `Demo@12345` | Drafts, uploads, preflight & brand checks, view own receipts/history |
| **Reviewer** | Bob | `reviewer@brandguard.demo` | `Demo@12345` | Review queue, approve/reject, coded overrides, clarity tickets, conflict resolution, library/rules/facts management, audit ledger |

> **Governance invariant:** Creators cannot approve their own checks (`409 Conflict` enforced by the API and database policy).

### Hosted Supabase Mode (`https://brandguard-app.antideploy.app`)
- Public local-demo credentials (`creator@brandguard.demo` / `Demo@12345`) **do not** work in Supabase mode.
- Earlier hosted evaluation credentials expired on **2026-11-17 01:30:31 IST** (`2026-11-16T20:00:31Z`).
- For hosted access, use **Create account → confirm email → Sign In** (grants Creator), and promote a trusted Reviewer/Admin via Supabase `app_metadata.brandguard_role` or `python manage.py create-user`. See [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md).

---

## 4. API Overview

All private endpoints require `Authorization: Bearer ACCESS_TOKEN`. Full OpenAPI schemas are available at `/docs` when running locally.

| Domain | Key Endpoints |
|---|---|
| **Auth & Profile** | `GET /api/v1/auth/config`, `POST /login`, `/signup`, `/refresh`, `/logout`, `/recover`; `GET /me`, `PATCH /profile`, `GET/PUT /preferences`, `PUT /password` |
| **Checks & Preflight** | `POST /api/v1/brand/preflight`, `POST /api/v1/brand/check`, `POST /api/v1/brand/{id}/versions`, `GET /api/v1/brand/rules/{brand_name}` |
| **Files & Visual/OCR** | `POST /api/v1/files` (TXT, MD, text PDF, PNG, JPG, JPEG, WEBP; `?as_fact=true` reviewer-only), `GET /files/{id}`, `GET /files/{id}/download` |
| **Reviews & Verify** | `GET /api/v1/reviews`, `PATCH /api/v1/reviews/{id}/decision`, `POST /api/v1/approvals/verify`, `POST /api/v1/approvals/verify-upload` |
| **Overrides & Tickets** | `POST /api/v1/reviews/{id}/findings/{finding_id}/override`, `GET /api/v1/overrides`, `GET /api/v1/clarity-tickets`, `PATCH /api/v1/clarity-tickets/{id}` |
| **Conflicts** | `GET /api/v1/conflicts/`, `GET /api/v1/conflicts/{id}`, `POST /api/v1/conflicts/{id}/resolve` |
| **Library** | `GET/POST/PUT/DELETE /api/v1/library/{guidelines,facts,rules}`, `POST /api/v1/library/rules/{rule_id}/logo-template` |
| **Workspace & Audit** | `GET/POST/PUT/DELETE /api/v1/drafts`, `GET /api/v1/receipts/`, `GET /receipts/{id}`, `GET /audit`, `GET /history`, `GET /analytics`, `GET/PATCH/DELETE /notifications`, `GET /system/status` |

---

## 5. Deployment & Hosted Notes

- Production entrypoint: **`serve.py`** (enforces `AUTH_PROVIDER=supabase` and `SEED_DEMO_USERS=false`, serves `browser_preview/` same-origin via `app.web:app`).
- Container build: **`Dockerfile`** installs `tesseract-ocr` and `backend/requirements.txt` on `python:3.13-slim`.
- Detailed operational checklists:
  - [START_HERE.md](START_HERE.md) — quickest local & hosted launch checklist
  - [DEPLOYMENT.md](DEPLOYMENT.md) — Antideploy setup, Round 3 redeploy checklist, and Supabase bucket MIME note
  - [docs/PROJECT_GUIDE.md](docs/PROJECT_GUIDE.md) — architecture, database/locking model, security boundaries
  - [docs/AI_SETUP.md](docs/AI_SETUP.md) — OpenRouter / OpenAI setup, free `:free` model notes, and grounded-output contract
  - [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md) & [docs/LIVE_SUPABASE_STATUS.md](docs/LIVE_SUPABASE_STATUS.md) — Supabase Postgres, Storage, and Auth email hook

---

## 6. Testing & Honest Boundaries

### Automated Verification
```bash
# Backend (from backend/)
pytest -q
# 145 tests total across tests/ + tests_secure/ (Phase 1-3 Round 3 + AI/workflow contracts):
# - Linux/Docker with tesseract-ocr: 145 passed
# - Without Tesseract binary installed locally: 143 passed, 2 OCR-binary tests skipped

# Flutter (from mobile/)
flutter analyze
flutter test
# Analyzer clean (0 issues); 134 Flutter tests across mobile/test/ (run locally with Flutter SDK)
```
*(Note: Historical evidence in `validation/` covers the pre-Round-3 `v2.0.1` hosted release and is preserved unchanged until Round 3 is redeployed and re-audited.)*

### Honest System Boundaries
- **Image OCR vs Scanned PDFs:** `PNG/JPG/JPEG/WEBP` banners run OCR via Tesseract when installed (`ocr_status` honestly reports when Tesseract is unavailable). Scanned image-only `.pdf` files still require PDF rasterization, which is not enabled (text-based PDFs up to 30 pages are supported).
- **Grounded AI Abstention:** When `AI_PROVIDER=disabled`, credits/key are missing, or no **reviewer-verified Fact Source** exists for the brand, AI explicitly returns `abstained` instead of fabricating factual checks.
- **Intentionally Unimplemented:** SSO/Okta/SAML buttons, 2FA/biometric attestation, automated web crawling, background push workers, and an unfinished Dark theme are intentionally omitted or marked clearly rather than mocked.
