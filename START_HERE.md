# BrandGuard — Start Here (v3.0.0 / Round 3)

> **Current focus:** **Local mode (`AUTH_PROVIDER=local`, SQLite `backend/data/brandguard.sqlite3`)** is the primary active workflow. Cloud Supabase migration/switchover is optional and currently deferred.

## 1. Run Locally on Your Laptop (Full Round 3 Experience)

### Requirements
- **Python 3.11+** (**3.13 recommended** — `fastapi==0.163.1` & `SQLAlchemy==2.1.8` do not support Python 3.10).
- **Optional (for local image OCR):** Tesseract OCR (`tesseract-ocr` on Linux/macOS, or `C:\Program Files\Tesseract-OCR\tesseract.exe` on Windows). Docker builds include it automatically.

### Launch Backend + Browser Web UI
From the repository root:

**Windows (PowerShell):**
```powershell
# First-time setup (creates backend\.venv, installs requirements, launches web app):
py -3 start_backend.py --web

# If `py` is not on PATH, use Python 3.13 directly:
& "$env:LocalAppData\Programs\Python\Python313\python.exe" start_backend.py --web

# Fastest repeat launch once backend\.venv exists:
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.web:app --host 0.0.0.0 --port 8000 --workers 1
```

**macOS / Linux:**
```bash
python3 start_backend.py --web
```

Open **http://127.0.0.1:8000/** (press `Ctrl+Shift+R` after any frontend rebuild).

### Local Demo Accounts (Local Mode Only)
- **Creator (`Alice`):** `creator@brandguard.demo` / `Demo@12345`
- **Reviewer (`Bob`):** `reviewer@brandguard.demo` / `Demo@12345`

---

## 2. Rebuild Frontend & Sync `browser_preview/`

Whenever you edit files under `mobile/`, rebuild the same-origin web bundle and copy it into `browser_preview/` (which `start_backend.py --web`, `serve.py`, and `Dockerfile` serve):

```powershell
cd mobile
flutter clean
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --no-web-resources-cdn

cd ..
Remove-Item browser_preview\* -Recurse -Force
Copy-Item mobile\build\web\* browser_preview\ -Recurse -Force
```

For native Android/iOS (`RUN_MOBILE.bat` / `RUN_MOBILE.sh`):
```bash
cd mobile
# Local backend on Android emulator (matches local SQLite backend):
flutter run --dart-define=API_BASE=http://10.0.2.2:8000

# Local backend in Chrome / Desktop:
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000

# Optional hosted app (Supabase mode):
flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
```

---

## 3. Enable Grounded AI Verification (Local Mode)

AI stays off (`AI_PROVIDER=disabled`) until a server key is configured in `backend/.env`:

1. **Windows:** Run **`ENABLE_AI.bat`** from the repo root (prompts cleanly for **Google Gemini free tier**, **OpenRouter**, or **OpenAI** without echoing the key, saves `backend/.env`, and tests the live model immediately).
   **macOS / Linux / CLI:**
   ```bash
   cd backend
   python manage.py configure-ai
   python manage.py test-ai
   ```
   *(Or manually place `GEMINI_API_KEY=...`, `OPENROUTER_API_KEY=...`, or `OPENAI_API_KEY=...` in `backend/.env` with `AI_PROVIDER` unset — BrandGuard auto-detects the provider.)*
2. Restart the backend (`START_BACKEND.bat` / `uvicorn`).
3. Sign in as Reviewer (`reviewer@brandguard.demo` / `Demo@12345`), open **Guidelines → Fact Sources**, tap **Test AI verification**, and add + **Verify** at least one Fact Source so live brand checks run grounded AI verification instead of abstaining.

See [docs/AI_SETUP.md](docs/AI_SETUP.md) for details.

---

## 4. Optional Hosted Supabase Mode (Deferred for Now)

- **Live URL:** **https://brandguard-app.antideploy.app** (optional cloud deployment on Antideploy with Supabase Auth/Postgres/Storage; local development does **not** require Supabase).
- **Accounts:** Earlier temporary evaluation accounts expired on **17 November 2026, 01:30:31 IST**. Create a personal Creator account via **Create account → confirm email → Sign In**, and assign Reviewer/Admin only through Supabase `app_metadata.brandguard_role` or `manage.py create-user`.
- **When redeploying Round 3 to Antideploy later:**
  1. Ensure `browser_preview/` has your fresh `flutter build web --no-web-resources-cdn` output.
  2. Update the Supabase `brandguard-files` bucket `allowed_mime_types` to also include `image/png`, `image/jpeg`, `image/webp` before uploading banners in cloud mode (see [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md)).
  3. Deploy via Antideploy using the existing app ID in `.antideploy.json` (see [DEPLOYMENT.md](DEPLOYMENT.md)).
