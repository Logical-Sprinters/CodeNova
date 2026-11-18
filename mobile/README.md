# BrandGuard — Mobile & Web Client (`mobile/`) — v3.0.0 (Round 3)

**Tagline:** *No finding without evidence. No approval without a version.*

Flutter mobile-first client (*Executive Precision* design system) connecting to the BrandGuard FastAPI backend. The same source compiles to Android/iOS/desktop and to the prebuilt CanvasKit web bundle stored in `../browser_preview/`.

---

## 1. Key Screens & Round 3 Capabilities

| Area | What's Implemented |
|---|---|
| **Navigation** | Fixed 5-tab shell: **Home · Workspace · Reviews · Guidelines · Profile** |
| **Auth Flow** | Splash, Sign In (server provider pill, local demo autofill only in local mode), Create Account, Forgot Password |
| **Home Dashboard** | Greeting hero, live metrics, decision mix, fast actions, brand filter, recent activity |
| **New Brand Check** | Exact-text editor, live preflight (`POST /api/v1/brand/preflight`), temporal `check_at` & `channel` selector, private document & image banner upload (`PNG/JPG/JPEG/WEBP` + OCR/palette/logo telemetry), policy summary |
| **Findings & Evidence** | Grounded rule cards (`rule_id`, `rule_version`, verbatim `rule_quote`, content/OCR span), AI abstention/evidence citations, reviewer coded finding overrides (`6` structured reasons), submit for review |
| **Review Queue** | Status filter (`pending`, `approved`, `rejected`, `paused_conflict`), exact-text inspection, approve/reject with notes, self-review prevention |
| **Governance Modules** | **Clarity Tickets** (rolled-up rule friction tickets), **Conflicts** (active rule/fact contradiction queue + resolution + `auto_recheck`), **Verify Approval** (`VALID` / `VOIDED_TAMPERED` + character/word diff + file re-verification) |
| **Guidelines Hub** | Shared **Brand Guidelines**, **Enforceable Rules** (temporal + channel + logo template upload), **Fact Sources** (reviewer verification gate) |
| **Receipts & Audit** | Structured `ReceiptDetailScreen` with hashes, grounding evidence, inline diff, and raw payload |
| **Profile** | Role pill, **My profile** full session & backend identity sheet + **Edit display name**, appearance & notification preferences (`PATCH /api/v1/auth/profile`, `GET/PUT /api/v1/auth/preferences`), backend status, logout |

---

## 2. Running & Building

### Prerequisites
- **Flutter 3.50.0 / Dart `^3.14.0`**
- Running backend (`https://brandguard-app.antideploy.app` by default for native builds, or local backend via `--dart-define=API_BASE=...`)

### Android / iOS / Emulator
```bash
cd mobile
flutter clean
flutter pub get --enforce-lockfile

# Native default (hosted API):
flutter run

# Local backend on Android emulator:
flutter run --dart-define=API_BASE=http://10.0.2.2:8000

# Local backend on physical phone (same Wi-Fi):
flutter run --dart-define=API_BASE=http://YOUR_PC_LAN_IP:8000
```

### Build & Sync Web Preview (`../browser_preview/`)
```powershell
cd mobile
flutter build web --no-web-resources-cdn

cd ..
Remove-Item browser_preview\* -Recurse -Force
Copy-Item mobile\build\web\* browser_preview\ -Recurse -Force
```
Then serve locally via Python 3.11+ (tested on 3.13):
```powershell
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.web:app --host 0.0.0.0 --port 8000 --workers 1
```

### Android Release APK (`lintVitalAnalyzeRelease` Note)
If `flutter build apk --release` fails inside third-party plugin lint (`List.removeLast()`), either configure JDK 21:
```powershell
flutter config --jdk-dir "C:\Program Files\Java\jdk-21"
flutter clean
flutter build apk --release
```
or rely on the existing `lintVital*` disable guard in `mobile/android/build.gradle.kts` (Dart checks still run via `flutter analyze` and `flutter test`).

---

## 3. Design System

- **Colors:** Navy `#142C3B`, Teal `#22A895`, Mint `#E8F5F1`, Canvas `#F7F8F5`, Card `#FFFFFF`, Border `#E5ECE9`, Danger `#D95D5D`, Warning `#E6A23C`
- **Typography:** Manrope, tabular figures for hashes/versions/metrics
- **Tokens & Shared Components:** `lib/app/app_theme.dart`, `lib/app/ui/app_widgets.dart`, `lib/app/ui/brandguard_shell.dart`

---

## 4. Testing

```bash
cd mobile
flutter analyze          # Expected: No issues found!
flutter test             # 124 tests (unit, connection/session, 5-viewport layout, Round 3 UI & My profile)
```

Viewport coverage includes **320×640, 360×780, 390×844, 430×932, and 768×1024** without render overflow.

---

## 5. Honest Boundaries

- **Auth & Roles:** Tokens stay in memory only (SharedPreferences is used strictly for non-secret email/UI preferences). Roles are enforced by the backend; no SAML/SSO/2FA/biometric claims are mocked.
- **Image OCR & PDFs:** Images (`PNG/JPG/JPEG/WEBP`) support OCR text extraction when Tesseract is installed on the backend (`tesseract-ocr`), plus dominant palette & perceptual logo checks. Scanned image-only `.pdf` files still require PDF rasterization, which is not enabled (text PDFs up to 30 pages are supported).
- **AI Abstention:** Findings explicitly show `abstained` when `AI_PROVIDER=disabled`, credits/keys are absent, or no verified Fact Source exists for the brand.
- **Theme:** Light theme (*Executive Precision*) is audited and shipped; dark mode is intentionally not partially faked.
