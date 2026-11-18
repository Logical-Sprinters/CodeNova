# BrandGuard — Redesigned Mobile App (v2.1.0)

BrandGuard ek **mobile-first brand governance app** hai: content likho, rules se check karao, aur
authorised reviewer se sign-off lo. Yeh version aapke bheje hue design references aur `DESIGN.md`
(Token: *Executive Precision*) ke hisaab se **poora UI/UX redesign** karta hai — backend, Supabase
data, logins aur flows **waise hi** hain jaise pehle the.

> Tagline: **No finding without evidence. No approval without a version.**

---

## 1. Kya naya hai (design)

| Area | Pehle | Ab |
|---|---|---|
| Navigation | Drawer/links | Fixed 5-tab bottom bar: Home · Workspace · Reviews · Guidelines · Profile |
| Design tokens | Ad-hoc colors | `AppTheme` mein centralized navy/teal palette, Manrope type ramp, radius + shadow tiers |
| Splash | Simple | Dark "VAULT SECURE" splash, verification ring, progress |
| Sign in | Plain form | Brand header, provider chip, secure password field, error/notice cards, demo accounts card (local only) |
| Sign up | Dialog | Full page: strength meter, confirm match, consent, role explanation |
| Forgot password | Dialog | Dedicated page, honest "provider sends the link" message |
| Home | Metric grid | Greeting hero + 4 metric cards + decision mix + fast actions + recent activity |
| Brand check | Plain form | Step strip, meta chips (words/chars/read time), attachments, policy engine summary |
| Findings | Long cards | Rule cards with severity pill, evidence block, replacement block, sticky submit bar |
| Review queue | List | Metrics + filter chips + rich review sheet + approval ledger |
| Guidelines | 3 lists | One Guidelines tab → Guidelines / Rules / Fact Sources overview |
| Profile | Basic | Avatar, role chip, grouped settings, appearance, backend status, danger-zone logout |
| Receipts | Raw key/value list | Structured receipt: hash chips, review state, evidence grounding, raw payload |

## 2. Chalane ke steps (baby steps)

### A. Android (emulator ya USB debug device)

1. ZIP extract karo.
2. `mobile` folder ke andar jao: `cd mobile`.
3. Pehli baar:
   ```bash
   flutter clean
   flutter pub get --enforce-lockfile
   ```
4. App run karo (hosted Supabase backend ke saath):
   ```bash
   flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
   ```
   Windows par ready-made launcher: `RUN_MOBILE.bat` (project root).
5. App khulne par splash → Sign In. Apne demo account se login karo (credentials alag private
   file mein diye gaye hain; woh is ZIP ke andar **nahi** hain).

### B. Browser preview (optional, fastest check)

```bash
cd mobile
flutter run -d chrome --dart-define=API_BASE=https://brandguard-app.antideploy.app
```

### C. Sirf design dekhna hai (backend ke bina)

Local backend chalao (`backend/README` ke mutabik) aur `--dart-define=API_BASE=http://10.0.2.2:8000`
(Android emulator) ya `http://localhost:8000` (web/desktop) use karo. Local mode mein hi public demo
accounts dikhte hain ("Local demonstration accounts" card). Cloud mode mein yeh card **kabhi nahi**
dikhta — wahan apna asli Supabase login use karo.

## 3. Design system (short)

- **Colors** — Navy `#142C3B` (authority), Teal `#22A895` (verification), Mint `#E8F5F1` (safe zones),
  Canvas `#F7F8F5`, Card `#FFFFFF`, Border `#E5ECE9`, Danger `#D95D5D`, Warning `#E6A23C`.
- **Type** — Manrope, mobile headline 26/34, body 14/20, micro labels 10/14 uppercase.
  Versions/hashes tabular figures mein.
- **Shape** — Inputs/buttons 8 px, cards 16–20 px, status pills 999 px.
- **Depth** — Cards: hairline border + soft ambient shadow. Bottom bar: frost + top hairline.
- **Spacing** — 16 px margins, 8 px rhythm, bottom content padding 26–96 px taaki bottom bar
  content ko na dhake.

Sab kuch `mobile/lib/app/app_theme.dart` (tokens/theme) aur `mobile/lib/app/ui/app_widgets.dart`
(reusable widgets: `SurfaceCard`, `StatusPill`, `MetricCard`, `InlineNotice`, `EmptyStateCard`,
`HashChip`, `ProgressLine`, `DetailRow`, `NavigationRow`, `InitialsAvatar`, `ErrorBlock`) mein hai.
Naya screen banate waqt inhi widgets ko use karo — design consistent rahega.

## 4. Pages jo working condition mein hain

Har page live REST API se data leta hai (mock/sample screens hata diye gaye hain), aur
loading / empty / error states dikhata hai (blank ya red screen nahi):

| Tab/Page | Backend calls |
|---|---|
| Splash | koi network call nahi |
| Sign in | `GET /api/v1/auth/config`, `POST /api/v1/auth/login` |
| Create account | `POST /api/v1/auth/signup` |
| Forgot password | `POST /api/v1/auth/recover` |
| Home | `/analytics`, `/notifications`, `/system/status` |
| Workspace hub | saare modules ka entry point |
| New brand check | `POST /api/v1/drafts`, `POST /api/v1/files` (upload), `POST /api/v1/brand/check` |
| Findings & evidence | `POST /api/v1/brand/{id}/versions` (submit) |
| Review queue | `GET /api/v1/reviews`, `PATCH /api/v1/reviews/{id}/decision` |
| Verify approval | `POST /api/v1/approvals/verify` |
| Guidelines / Rules / Fact sources | `GET/POST/PUT/DELETE /api/v1/library/{kind}` |
| Analytics | `GET /api/v1/analytics` |
| Notifications | `GET/PATCH/DELETE /api/v1/notifications` |
| Drafts | `GET/POST/PUT/DELETE /api/v1/drafts` |
| Version history / Audit ledger | `GET /api/v1/history`, `/api/v1/audit` |
| Processing receipts | `GET /api/v1/receipts/`, `GET /api/v1/receipts/{id}` |
| Profile | `GET /api/v1/system/status`, `POST /api/v1/auth/logout` |

## 5. Honesty notes (kya jaan-boojh kar nahi dikhaya)

Design references mein kuch cheezein dikhayi gayi thi jo is backend/app mein **nahi** hain. Unhe
dikhana galat hoga, isliye humne unhe honest tareeke se handle kiya:

1. **SAML/Okta/SSO button** — hata diya. Sign in Supabase email+password ya local auth se hota hai.
2. **AI/magic claims ("100% uptime", "SOC 2 certified", "AES-256 HSM")** — marketing text ki tarah
   nahi lagaya. App sirf wahi dikhata hai jo server bataata hai.
3. **OCR (image se text)** — "OCR Text Extracted" jaisa fake badge nahi. Upload sirf TXT/MD/text-PDF
   par kaam karta hai, aur screen par yahi likha hai.
4. **Biometric/hardware attestation, 2FA** — implement nahi hai, isliye UI mein claim nahi hai.
5. **Organisation/tenant model** — sign-up page organisation name leta hai lekin saaf likhta hai ki
   server par abhi organisation model nahi hai.
6. **"Request changes"** — UI mein hai, lekin backend sirf `approved`/`rejected` supports karta hai,
   isliye "changes requested" note ke saath `rejected` record hota hai (pehle se same behaviour).
7. **AI comparison** — `AI_PROVIDER=disabled` hai, isliye findings screen par "AI comparison:
   abstained" saaf dikhta hai. AI funded hone par hi real comparison hoga.
8. **Dark theme** — token ke hisaab se light theme audited + shipped hai; dark/system par tap karne se
   honest snackbar aata hai (aadhi-adhoori dark theme nahi dikhayi).

## 6. Testing / quality

Is delivery par jo actually chalaya gaya (reproducible commands):

```bash
cd mobile
flutter analyze                 # No issues found!
flutter test --concurrency=1    # 91 tests, All tests passed!
cd ../backend
pytest -q                       # 113 passed
```

Live browser verification (Playwright, real hosted API, Creator + Reviewer dono):

| Check | Result |
|---|---|
| Supabase login (real) | 200, token mila, role gate sahi |
| `/api/v1/auth/config`, `/analytics`, `/notifications`, `/system/status`, `/reviews`, `/api/v1/library/*` | sab 200 |
| Runtime JS errors | 0 |
| Failed resources | 0 |
| Logout | 200 (per session) |
| Screens walked | sign-in, home, workspace + 9 modules, review queue + review sheet, guidelines + rules library, fact sources, profile, analytics, receipts |
| Screens 320×640 / 480×1000 | koi overflow banner nahi, koi red screen nahi |

Suite kya cover karta hai:

- Splash → Sign In flow, local demo autofill, cloud mode mein demo values hidden.
- Galat password, offline server, remember-email (tokens kabhi preferences mein nahi).
- Signup page validation + consent gate, forgot-password page error honesty.
- Har screen **320×640, 360×780, 390×844, 430×932, 768×1024** par bina overflow render hoti hai
  (yehi "pixel error" ka automated guard hai). Browser par bhi 320 px aur 480 px par koi
  `overflowed by … pixels` error nahi aaya.
- Bottom navigation ke paanchon tab, workspace ke saare modules, guidelines ke teen modules.
- Exact-content check call (untrimmed body), draft revision protection, notification mark-read,
  receipt loading/dispose safety.

## 6b. ZIP ke andar kya hai

```
mobile/                 # Flutter source (main app) — lib/, test/, android/, ios/, web/
backend/                # FastAPI backend (Supabase mode) — app/, tests/
browser_preview/        # Ready-made web build (19 MB) — server par kuch build karne ki zaroorat nahi
validation/             # Test/build evidence logs
README.md               # Yeh file
```

`browser_preview/` ko kisi bhi static server se kholo (e.g. `python serve.py`) — wahi build hai jo
live browser verification se pass hua. Iske andar tokens/passwords kuch nahi hai.

**Is ZIP ke andar jaan-boojh kar NAHI hai:** `.env` (server credentials), demo account passwords
(private file alag), `build/`, `.dart_tool/`, keystore.

## 6c. APK build error (agar aaye): `lintVitalAnalyzeRelease` crash

Poora error message aisa dikhta hai:

```
Execution failed for task ':file_selector_android:lintVitalAnalyzeRelease'
> Unexpected failure during lint analysis (this is a bug in lint ...)
  Message: 'java.lang.Object java.util.List.removeLast()'
```

**Yeh aapke app code ka bug nahi hai.** Release APK banate waqt Gradle ek extra "vital lint"
analysis chalata hai. Woh analysis third-party plugin ke Java file
(`file_selector_android/.../FileUtils.java`) par jaati hai aur lint ke andar hi crash ho jaati hai:
`List.removeLast()` sirf **Java 21+** mein hai, lekin lint khud usse call karta hai — isliye purane
JDK par `NoSuchMethodError` aata hai.

**Fix 1 (recommended, permanent): Gradle ko JDK 21+ par chalao**

```powershell
flutter config --jdk-dir "C:\Program Files\Java\jdk-21"
flutter clean
flutter build apk --release
```

(Jab JDK 21 ho, yeh crash root se khatam ho jaata hai.)

**Fix 2 (ZIP mein pehle se laga hua hai): lint crash ko build rokne se roko**

Is ZIP ke `android/build.gradle.kts` mein safety net already hai — `lintVital*` tasks skip ho jaate
hain, isliye build aage badh jaata hai. Check karne ke liye:

```powershell
cd mobile\android
Select-String -Path build.gradle.kts -Pattern "lintVital"
```

Agar aap purana folder (`BrandGuard-Mobile-Clean`) use kar rahe ho, to in do lines ko
`mobile/android/build.gradle.kts` ke aakhir mein paste kar do:

```kotlin
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital")) {
            enabled = false
        }
    }
}
```

**Quick workaround (agar turant APK chahiye):**

```powershell
flutter build apk --release --no-shrink
```
Ya debug APK: `flutter build apk --debug` (yeh lint nahi chalata).

Lint skip karne ka matlab "code unchecked" nahi hai — Dart side `flutter analyze` (No issues) aur
`flutter test` (91 passed) se poora check hota hai; skip sirf Android lint ke crash ko bypass karta hai.

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| Sign in par timeout | `API_BASE` galat ya device se internet nahi. Hosted URL use karo; purani IDE `--dart-define` override hata do. |
| Blank/red screen | `flutter clean && flutter pub get --enforce-lockfile` phir dobara run karo (design update ke baad rebuild zaroori hai). |
| "Multiple exceptions/overflow" purane screenshot mein | Naye build mein fix hai; tests 5 screen sizes par overflow check karte hain. |
| Demo account card nahi dikh raha | Woh sirf **local** server par dikhta hai. Cloud par normal login karo. |
| Reset link email nahi aaya | Supabase SMTP/limit check karo; app saaf-saaf batata hai jab email reset available nahi hai. |

## 8. Repo structure (important)

```
mobile/
  lib/app/app_theme.dart          # design tokens + Material theme
  lib/app/ui/app_widgets.dart     # shared visual vocabulary
  lib/app/ui/brandguard_shell.dart# 5-tab bottom navigation shell
  lib/features/...                # screens (auth, dashboard, checks, reviews, guidelines, ...)
  test/                           # widget + layout regression tests
backend/                          # FastAPI + Supabase (unchanged)
```

Backend code, Supabase project, rules aur data **is redesign ke chalu hone se change nahi hue**.
Koi deployment/seed/migration is ZIP ke saath nahi chalti.
