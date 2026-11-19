# BrandGuard — Live Deployment Handoff & Round 3 Redeploy Guide

> **Round 3 (v3.0.0) Note:** Cloud Supabase / Antideploy redeploy is currently **optional / deferred** in favor of local SQLite development (`START_HERE.md`). The verification counts (`113` backend / `49` Flutter / `55` API / `17` email) below describe the initial `v2` Antideploy deployment in `validation/antideploy/`. Round 3 adds server-side grounding, temporal rules, conflicts, coded overrides, clarity tickets, visual/OCR inspection (`tesseract-ocr` in `Dockerfile`), real-time creator/reviewer workflows (`changes_requested` + Edit & Resubmit, 60-minute `POST /api/v1/reviews/{id}/amend` decision reversal + `REVOKED` seals, in-app Password change, two-step inspect → Submit for authorised review, newest-first queues, creator/timestamp metadata, Light-mode default, Unseen/Seen notifications, Remember me session restore, non-destructive `Edit as new check` for Approved submissions, Profile stack-card cleanup, and Fact Sources `Test AI verification`), and updated Flutter screens (`153` backend pytest cases / `10` Flutter test files). Follow the **Round 3 Redeploy Checklist** below if/when updating the live URL.

## Live Links

- **App:** https://brandguard-app.antideploy.app
- **Health:** https://brandguard-app.antideploy.app/health
- **Antideploy dashboard:** https://antideploy.com/app/24f672f9-ef5a-4c45-8043-b98af546e6ad
- **App ID (`.antideploy.json`):** `24f672f9-ef5a-4c45-8043-b98af546e6ad` (always redeploy to this same app; never create a duplicate app)

---

## Round 3 Redeploy Checklist

1. **Rebuild & sync `browser_preview/`** so `serve.py` / `Dockerfile` ship the Round 3 Flutter UI (including the `My profile` fix):
   ```powershell
   cd mobile
   flutter analyze
   flutter test
   flutter build web --no-web-resources-cdn
   cd ..
   Remove-Item browser_preview\* -Recurse -Force
   Copy-Item mobile\build\web\* browser_preview\ -Recurse -Force
   ```
2. **Allow banner image MIME types in Supabase Storage** *(required for Round 3 image uploads in cloud mode)*:
   Run in Supabase SQL Editor on `jtidayzktuzpjydshsva`:
   ```sql
   UPDATE storage.buckets
   SET allowed_mime_types = ARRAY[
     'text/plain', 'text/markdown', 'application/pdf',
     'image/png', 'image/jpeg', 'image/webp'
   ]
   WHERE id = 'brandguard-files';
   ```
   *(Already reflected in `backend/supabase/002_private_storage.sql` comments/instructions in [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md).)*
3. **Check `Dockerfile` & `backend/requirements.txt`:**
   - `Dockerfile` installs `tesseract-ocr` (`apt-get install`) and `pillow`, `pytesseract`, `numpy` from `backend/requirements.txt`.
4. **Provision fresh judge / reviewer accounts:**
   - Earlier temporary evaluation credentials (`brandguard_access_until = 2026-11-16T20:00:31Z`) expired on **17 November 2026, 01:30:31 IST**.
   - Create fresh accounts via **Create account → confirm email → Sign In** (Creator) and assign Reviewer via Supabase `app_metadata.brandguard_role = "reviewer"` or `python manage.py create-user`.
5. **Redeploy to the existing Antideploy app** (and optionally add AI credits/env vars + at least 1 **Verified Fact Source** in the UI if testing live AI).

---

## Initial Deployment Verification (Historical `v2` Baseline)

| Area | Verified result |
|---|---|
| Deployment | Custom Dockerfile built and deployed successfully, HTTPS public URL tested |
| Runtime | Non-root Python 3.13, one Uvicorn worker, `app.web:app`, platform PORT/0.0.0.0 |
| Mobile-first UI | Same Flutter source in `mobile/`; bundled CanvasKit web build serves on the API origin |
| Database/Auth/files | Existing BrandGuard Supabase preserved, verified-TLS PostgreSQL, private Storage |
| Roles | Creator and Reviewer actual rendered browser sign-in at 430×932, real dashboard responses |
| Workflows | **55 public API acceptance checks passed**, including files, drafts, scan, approvals, notifications and sessions |
| Auth email | Signed Supabase Send Email Hook → Antideploy relay; sender `brandguard-app@mail.antideploy.com` |
| Delivery | **5 accepted / 5 provider-reported delivered**, no bounces/complaints in the test snapshot |
| Callbacks/recovery | **17 real checks passed**: confirmation, reset, old/new password, logout, one-use link denial |
| Regressions | **113 backend + 49 Flutter tests passed; analyzer clean** (pre-Round-3 baseline) |
| Security | CSP/header finding fixed and redeployed; automatic and full platform scans had **0 findings** |
| Cleanup | Temporary Auth users, objects and test-brand rows removed; intended demo/sample preserved |

Full historical scan report: https://antideploy.com/security/scan/ee8aaa4a-ac9c-4aff-90ae-b69298559f2d .

---

## Access & Role Rules

- Public signup grants **Creator** (`role=creator`) and requires email confirmation.
- Public signup cannot grant Reviewer/Admin. A trusted administrator must assign `{"brandguard_role": "reviewer"}` in Supabase `app_metadata` (or provision via `manage.py create-user`).
- Earlier evaluation Creator/Reviewer logins expired on **17 November 2026, 01:30:31 IST** (`2026-11-16T20:00:31Z`). Normal accounts without `brandguard_access_until` do not expire.

---

## AI Configuration

- Server-side `OPENROUTER_API_KEY` is provisioned on Antideploy (`AI_BASE_URL=https://openrouter.ai/api/v1`, `AI_MODEL=openai/gpt-5.4-mini`).
- **Default `AI_PROVIDER=disabled`** while wallet balance is **₹0**. Rules, temporal checks, conflicts, OCR/visual checks, clarity tickets, and approvals all work free.
- To enable paid AI on Antideploy: top up at https://antideploy.com/settings/billing#add-money (**15% fee:** ₹100 credit = ₹115), set `AI_PROVIDER=openrouter` in Antideploy env vars, redeploy, and add + **Verify** a Fact Source in the app. See [docs/AI_SETUP.md](docs/AI_SETUP.md) for free `:free` model testing options too.

---

## Operational Limits & Maintenance

- Native email relay: **20 recipient-addresses per rolling day**, 10 messages/minute, max 5 recipients/message. Supabase auth-email throttle is 20/hour.
- Site URL is `https://brandguard-app.antideploy.app`; exact `/auth/confirm` and `/auth/reset` redirects are allowlisted; `/api/v1/auth/hooks/email` requires signed Standard Webhooks HMAC validation.
- Normal runtime holds no Supabase service-role key. `serve.py` runs from `backend/` so `certs/supabase-prod-ca-2021.crt` resolves under `sslmode=verify-full`, and refuses `AUTH_PROVIDER=local` or `SEED_DEMO_USERS=true`.
- Reuse `.antideploy.json`'s app ID on every deploy; never overwrite native relay/AI platform variables.

Native Flutter client against hosted API:

```sh
cd mobile
flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
```
