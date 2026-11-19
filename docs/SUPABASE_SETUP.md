# BrandGuard Supabase — Maintain the Existing Hosted Setup

> **Current Status:** Optional / deferred for local development. Active local runs use SQLite + local JWT (`AUTH_PROVIDER=local`) by default — see [../START_HERE.md](../START_HERE.md). Use this guide only when switching back to or redeploying hosted Supabase mode.

**Current app:** https://brandguard-app.antideploy.app . Hosting and real auth-email
callbacks are already deployed; do not redo project creation or choose another
provider. See [LIVE_SUPABASE_STATUS.md](LIVE_SUPABASE_STATUS.md) and
[DEPLOYMENT.md](../DEPLOYMENT.md).

## Existing Infrastructure

- **Project:** `jtidayzktuzpjydshsva`, BrandGuard, Mumbai `ap-south-1`.
- **API:** `https://jtidayzktuzpjydshsva.supabase.co`.
- **Dashboard:** https://supabase.com/dashboard/project/jtidayzktuzpjydshsva .
- **Pooler:** `aws-1-ap-south-1.pooler.supabase.com:5432`, database `postgres`,
  login `postgres.jtidayzktuzpjydshsva`.
- Core (`001_core.sql`), private Storage (`002_private_storage.sql`), and evaluation-expiry migrations are already applied.
- LiFE Mitra Gujarat (`zaljyzpxcnrugmyjlhuc`) remains untouched. Do not recreate or replace its data.

## Backend Secret Boundary

Production variables include `AUTH_PROVIDER=supabase`, `SEED_DEMO_USERS=false`,
project URL/publishable key, private `DATABASE_URL`, bucket name, and auth callback
configuration. **No normal runtime Supabase service/admin key is required.**

`DATABASE_URL` uses `sslmode=verify-full` with `certs/supabase-prod-ca-2021.crt`.
`serve.py` sets `backend/` as the working directory so relative cert paths resolve cleanly; never disable TLS verification.

`serve.py` refuses local/demo Auth in production (`AUTH_PROVIDER=local` or `SEED_DEMO_USERS=true`).

## Native Flutter

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

Native builds default to `https://brandguard-app.antideploy.app`. Web stays same-origin (`browser_preview/`). Pass `--dart-define=API_BASE=...` only for local/emulator development.

## Trusted Roles & Private Documents (Round 3 Storage Update)

- Public signup creates confirmed **Creator** accounts. Never use client-editable `user_metadata` for roles.
- Assign Reviewer/Admin only via trusted `app_metadata` (`{"brandguard_role": "reviewer"}`) or `python manage.py create-user`.
- **`brandguard-files` Storage bucket (5 MB limit):**
  - Initial `v2` setup allowed `text/plain`, `text/markdown`, and `application/pdf`.
  - **Round 3 adds image banner uploads (`PNG`, `JPG`, `JPEG`, `WEBP`).** Before testing image uploads against Supabase Storage, run this in the Supabase SQL Editor so the bucket accepts images:
    ```sql
    UPDATE storage.buckets
    SET allowed_mime_types = ARRAY[
      'text/plain', 'text/markdown', 'application/pdf',
      'image/png', 'image/jpeg', 'image/webp'
    ]
    WHERE id = 'brandguard-files';
    ```
- **Evaluation expiry note:** Earlier temporary evaluation users had `brandguard_access_until` expiring **2026-11-16T20:00:31Z** (**17 November 2026, 01:30:31 IST**). That window has now passed; create fresh user/reviewer accounts for new evaluations. Ordinary accounts without `brandguard_access_until` never expire.

## Auth Email Configuration

- **Site URL:** `https://brandguard-app.antideploy.app`
- **Allowlisted redirects:** `/auth/confirm` and `/auth/reset`
- **Send Email Hook:** `/api/v1/auth/hooks/email` (Standard Webhooks HMAC/timestamp validated)
- **Relay:** Native Antideploy transactional relay (`20` recipient-addresses/rolling day; Supabase throttle `20`/hour). Do not replace with manual SMTP or shadow `RESEND_*`/`EMAIL_FROM`.

## Operations & AI

- Retain PostgreSQL (`pg_dump`) + Storage object backups alongside `manage.py backup`.
- AI setup is documented in [AI_SETUP.md](AI_SETUP.md).
