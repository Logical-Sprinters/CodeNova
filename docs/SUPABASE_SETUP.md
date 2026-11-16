# BrandGuard Supabase — maintain the existing hosted setup

**Current app:** https://brandguard-app.antideploy.app . Hosting and real auth-email
callbacks are already deployed/tested; do not redo project creation or choose another
provider. See [LIVE_SUPABASE_STATUS.md](LIVE_SUPABASE_STATUS.md) and
[DEPLOYMENT.md](../DEPLOYMENT.md). Earlier standalone/local-demo ZIPs stay unchanged.

## Existing infrastructure

- Project: `jtidayzktuzpjydshsva`, BrandGuard, Mumbai `ap-south-1`.
- API: `https://jtidayzktuzpjydshsva.supabase.co`.
- Dashboard: https://supabase.com/dashboard/project/jtidayzktuzpjydshsva .
- Pooler: `aws-1-ap-south-1.pooler.supabase.com:5432`, database `postgres`,
  login `postgres.jtidayzktuzpjydshsva`.
- Core, private Storage and temporary-evaluation-expiry migrations are already applied.
  SQL files document provisioning for another explicitly authorized environment only.
- LiFE Mitra Gujarat remains untouched. Do not recreate/replace its or this project's data.

## Backend secret boundary

Normal production variables include `AUTH_PROVIDER=supabase`, `SEED_DEMO_USERS=false`,
project URL/publishable key, private `DATABASE_URL`, bucket name and auth callback
configuration. They are encrypted host variables; a private local `.env` is 0600 and
not source-uploaded. **No normal runtime Supabase service/admin key is needed.**

The database URL uses `sslmode=verify-full` plus the bundled PUBLIC CA
`certs/supabase-prod-ca-2021.crt`. `serve.py` sets `backend/` as working directory.
For another environment, use a valid server-local absolute CA path if necessary;
never disable certificate/hostname validation to fix a relative-path mistake.
Database credentials and real signing/provider secrets must never be placed in
Flutter, Git, source archives, screenshots or chat.

The production entrypoint refuses local/demo Auth and never seeds/replaces users.
Use the earlier ready-demo ZIP for an intentionally isolated local SQLite demo,
not public seeded accounts on this live host.

## Native Flutter

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

Native defaults to the existing hosted HTTPS API; no dart-define is required.
Web uses its own origin. Only explicit local development should pass a different
API_BASE; a phone must never rely on the computer/emulator localhost. `mobile/` is the only Flutter root. Native
release/device/signing certification is separate from this hosted web/API deployment.

## Trusted roles and private documents

Public signup → confirmed Creator. Never trust `user_metadata` or a dropdown to
assign Reviewer/Admin. A trusted administrator may update only the intended user's
`app_metadata` to include `{"brandguard_role":"reviewer"}` (or an authorized admin
role), preserving its other fields. Supabase's `role=authenticated` is different.
A permanent owner/reviewer identity was not silently created by the deploy.

A trusted, private admin environment can use `manage.py create-user`; its temporary
admin credential must not enter the running app. The command prompts for a password
and creates an admin-confirmed identity, so it is not evidence of email delivery.
A reviewer should log in once so notification recipients are known to the app.

`brandguard-files` is private with 5 MB TXT/Markdown/PDF limits. User bearer tokens,
not a runtime service key, authorize actual object operations. Owner-folder uploads
and owner/trusted-reviewer reads are enforced; anonymous/other-creator access is denied.

Two intended evaluation users and their sample remain until the unchanged app/Storage
expiry **17 November 2026, 01:30:31 IST**. Ordinary users without the trusted expiry
flag are unaffected. Do not indiscriminately clean/recreate intended users or files.

## Auth email already configured

- Site URL: `https://brandguard-app.antideploy.app`.
- Exact allowlisted callbacks: `/auth/confirm` and `/auth/reset`, with the prior root URLs retained.
- Send Email Hook: `/api/v1/auth/hooks/email`, protected by Standard Webhooks HMAC/timestamp validation.
- Relay: native Antideploy Resend-compatible variables and sender, 20 recipients/day.
- Supabase auth-email throttle: 20/hour; relay's stricter day cap still applies.
- Confirmation is enabled. A confirmation link returns to a token-clearing page;
  recovery link returns to the same-origin reset form. Used recovery links are denied.

Do not add SMTP credentials or shadow the native `RESEND_*`/`EMAIL_FROM` variables:
the signed hook replaces SMTP for this application. No Resend account or email-domain
DNS changes are required by this chosen relay. Email-address-change double
confirmation is not an implemented app feature; unsupported hook actions fail closed.
The five test sends were all provider-reported delivered; human inbox opening is not claimed.

## Operations still separate

Retain backups of PostgreSQL and private objects, and test a cloud restore before
claiming disaster recovery. Current repository serialization favors consistency over
throughput; load/tenancy/background jobs are not newly implemented. In-app decision
notifications are not push/transactional product emails. AI is separately disabled
until the owner's Antideploy wallet is funded; see [AI_SETUP.md](AI_SETUP.md).
