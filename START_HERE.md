# BrandGuard — Start Here (v3.0.0 / Round 3)

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
flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
# Or for local backend on Android emulator:
flutter run --dart-define=API_BASE=http://10.0.2.2:8000
```

---

## 3. Public Hosted App & Round 3 Deployment Notes

- **Live URL:** **https://brandguard-app.antideploy.app** (hosted on Antideploy with Supabase Auth/Postgres/Storage).
- **Accounts:** Earlier temporary evaluation accounts expired on **17 November 2026, 01:30:31 IST**. Create a personal Creator account via **Create account → confirm email → Sign In**, and assign Reviewer/Admin only through Supabase `app_metadata.brandguard_role` or `manage.py create-user`.
- **Redeploying Round 3 to Antideploy:**
  1. Ensure `browser_preview/` has your fresh `flutter build web --no-web-resources-cdn` output.
  2. Update the Supabase `brandguard-files` bucket `allowed_mime_types` to also include `image/png`, `image/jpeg`, `image/webp` before uploading banners in cloud mode (see [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md)).
  3. Deploy via Antideploy using the existing app ID in `.antideploy.json` (see [DEPLOYMENT.md](DEPLOYMENT.md)).
- **AI Mode:** Currently `AI_PROVIDER=disabled` by default (deterministic rules, temporal checks, conflict detection, OCR/palette/logo checks, clarity tickets, and tamper-proof approvals all work without an AI key). To enable live AI comparison or Vision inspection, see [docs/AI_SETUP.md](docs/AI_SETUP.md) and remember to add + **Verify** at least 1 Fact Source under **Guidelines → Fact Sources**.
