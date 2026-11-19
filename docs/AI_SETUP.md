# BrandGuard AI — Grounded Text & Multimodal Vision Configuration

## 1. Local Setup (Recommended — 60-Second Guided Wizard)

By default, `AI_PROVIDER=disabled` so deterministic rules, temporal/channel resolution, conflict detection, OCR/palette/logo visual inspection, clarity tickets, and human review all run at **$0** without a provider key (AI fields explicitly return `abstained`).

### Fastest Way to Enable Live AI Locally
1. **Run the interactive setup script** (saves directly to `backend/.env` with hidden key input and immediately runs a live probe):
   - **Windows:** Double-click or run **`ENABLE_AI.bat`** from the repo root.
   - **macOS / Linux / CLI:**
     ```bash
     cd backend
     python manage.py configure-ai
     ```
2. **Test anytime from terminal or UI:**
   - **Terminal:** `python manage.py test-ai` (from `backend/`)
   - **In-App (Reviewer):** Restart the backend (`START_BACKEND.bat` / `uvicorn`), open **Guidelines → Fact Sources**, and tap **Test AI verification** (`POST /api/v1/system/ai-test`).
   - **In-App Chatbot (Creator & Reviewer):** Tap the floating chat icon in the **bottom-right corner** of the main shell to open the **BrandGuard AI** chat box (`POST /api/v1/assistant/chat`) for grounded Q&A and draft copy pre-checks (with automatic deterministic fallback if AI is off or rate-limited).

> **Auto-detection:** If you edit `backend/.env` manually and set `GEMINI_API_KEY` (or `GOOGLE_API_KEY`), `OPENROUTER_API_KEY`, or `OPENAI_API_KEY` while leaving `AI_PROVIDER` unset/blank, BrandGuard automatically activates that provider. Explicit `AI_PROVIDER=disabled` overrides any key.

---

## 2. Supported Providers (`backend/.env` Server-Only)

- **Google Gemini free tier (recommended $0 option):**
  ```dotenv
  AI_PROVIDER=gemini
  AI_API_KEY=YOUR_GEMINI_API_KEY
  AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai
  AI_MODEL=gemini-3.5-flash-lite
  ```
  *(Note: New Google AI Studio keys require Gemini 3.x models such as `gemini-3.5-flash-lite` or `gemini-3.8-flash` instead of legacy `gemini-2.5-flash`; if an older model ID returns HTTP 404, BrandGuard automatically falls back across active Gemini Flash models.)*
- **OpenRouter `:free` models** (`$0` balance accounts allow **20 requests/min** and **50 requests/day**):
  ```dotenv
  AI_PROVIDER=openrouter
  AI_API_KEY=YOUR_OPENROUTER_KEY
  AI_BASE_URL=https://openrouter.ai/api/v1
  AI_MODEL=nvidia/nemotron-3-super-120b-a12b:free
  ```
  *(Note: Paid OpenRouter models still default to `data_collection: deny`; `:free` models automatically omit `data_collection: deny` unless `AI_DATA_COLLECTION=deny` is set and fall back cleanly to `json_object` when a free model rejects strict `json_schema`, while keeping full Pydantic + server-side grounding checks.)*
- **Direct OpenAI:**
  ```dotenv
  AI_PROVIDER=openai
  AI_API_KEY=YOUR_OPENAI_API_KEY
  AI_BASE_URL=https://api.openai.com/v1
  AI_MODEL=gpt-5.4-mini
  ```

### Optional Hosted Mode (Antideploy — Deferred/Optional)
- Antideploy's hosted `OPENROUTER_API_KEY` path remains server-side only with `AI_PROVIDER=disabled` while wallet balance is **₹0** (`https://antideploy.com/settings/billing#add-money` if ever enabled on hosted Antideploy). Do **not** copy keys into `mobile/` or git.

---

## 3. Grounded-Output Contract (Applies to Both Copy & Vision)

Even when AI is enabled, BrandGuard **never runs ungrounded AI checks**:

1. **Verified Fact Source Required:** A reviewer must add (or upload via `POST /api/v1/files?as_fact=true`) and explicitly mark **Verify** on at least one **Fact Source** for that brand under **Guidelines → Fact Sources**. If zero active verified Fact Sources exist for `brand_name` at `check_at` / `channel`, AI **abstains immediately** (0 API tokens spent).
2. **Lexical Passage Retrieval (`app/checks/llm/verifier.py`):** Enabled verified facts active at `check_at` are split into overlapping 3,000-character passages (2,700-character stride), ranked by lexical overlap, and up to 5 passages are sent alongside up to 12,000 characters of copy.
3. **Multimodal Vision Inspection (`app/checks/visual/inspector.py`):** When an image banner is attached and AI is configured alongside verified brand/visual rules, the same provider/key settings govern visual inspection; otherwise deterministic palette (`VIS-02`), perceptual logo hash (`VIS-05`), and Tesseract OCR (`image_ocr`) run locally and Vision AI explicitly abstains.
4. **Strict Server Validation:** OpenAI/paid-OpenRouter calls enforce `response_format: json_schema` (`strict: true`), `store: false`, `require_parameters: true` + `data_collection: deny`, a 3,000-token cap, and a 25-second timeout (`AI_PROVIDER=gemini` omits OpenAI-only `store` and uses `max_tokens: 3000`).
5. **Post-Response Grounding Gate (`app/checks/grounding.py`):** The server verifies every returned `fact_id`, verbatim source quote, source hash, content/OCR span, and status consistency. Invalid or ungrounded AI outputs are **dropped / abstained** and logged.
6. **Human Sign-Off Mandatory:** AI findings are advisory evidence only; publication requires independent reviewer approval.

---

## 4. Live Acceptance Checklist (After Enabling a Key)

1. Run `ENABLE_AI.bat` (or `python manage.py configure-ai` / `test-ai`) and confirm **Live AI verification SUCCEEDED**.
2. Add & **Verify** a Fact Source for your test brand under **Guidelines → Fact Sources** (and optionally tap **Test AI verification** there).
3. Test three cases in **New Brand Check**:
   - A claim directly **supported** by the verified Fact Source.
   - A claim **contradicting** the verified Fact Source (`AI-FACT-*` finding + verbatim quote).
   - An **unsupported** claim with no matching fact (`abstained` / unverified notice).
4. Test an **image banner** with embedded prohibited text to verify OCR (`image_ocr`) + visual checks + Vision AI behavior.

*Note: Image OCR (`tesseract-ocr`) is included in Round 3. Web crawling, scanned-PDF rasterization, spend-tracking UI, and async inference queues are intentionally not included.*
