# BrandGuard — Hosted Supabase Status

> **Current Status:** Deferred/optional for local development (`AUTH_PROVIDER=local` SQLite is active locally; see [../START_HERE.md](../START_HERE.md)). Existing Supabase infrastructure documented below remains untouched if needed later.

## Existing Project Preserved

| Item | State |
|---|---|
| Project | BrandGuard, `jtidayzktuzpjydshsva`, Mumbai `ap-south-1` |
| API | https://jtidayzktuzpjydshsva.supabase.co |
| Public app/API | https://brandguard-app.antideploy.app |
| Domain persistence | FastAPI → PostgreSQL, official CA + hostname `verify-full` |
| Auth | Email/password, signup + confirmation enabled; JWT 1800s; refresh rotation |
| Storage | Private `brandguard-files` bucket (5 MB limit; see Round 3 image MIME note below) |
| Auth Site URL | https://brandguard-app.antideploy.app |
| Exact callback paths | `/auth/confirm` and `/auth/reset`, plus app root |
| Send Email Hook | Enabled (Standard Webhooks HMAC → Antideploy relay) |
| Auth/relay limits | Auth 20/hour; native relay 20 recipient-addresses/day |
| Runtime admin key | Not required and not in deployed runtime |

LiFE Mitra Gujarat (`zaljyzpxcnrugmyjlhuc`) was not modified. Existing migrations
`20261115192757`, `20261115192825`, and `20261115195921` remain intact.

## Round 3 Storage Note

Round 3 adds multimodal image banner uploads (`.png`, `.jpg`, `.jpeg`, `.webp`).
Ensure `storage.buckets.allowed_mime_types` for `brandguard-files` includes `'image/png'`, `'image/jpeg'`, and `'image/webp'` (see [SUPABASE_SETUP.md](SUPABASE_SETUP.md)) before uploading images in Supabase mode.

## Evaluation Access Note

The two earlier temporary evaluation accounts and their non-confidential sample had `brandguard_access_until` set to **2026-11-16T20:00:31Z** (**17 November 2026, 01:30:31 IST**). That expiry timestamp has now passed. Normal accounts created via **Create account** (and Reviewers granted `app_metadata.brandguard_role`) do not expire.

## Historical `v2` Verification Snapshot

The verification logs in `../validation/antideploy/` record checks executed on the initial `v2` deployment:
- 22 direct Auth/REST/Storage checks + TLS verification
- 55 public API workflow checks, SQL read/rollback, cleanup
- 17 real signup/confirmation/recovery/browser callback checks
- 5/5 relay-reported email deliveries

*(Round 3 adds new backend endpoints, Tesseract OCR/visual inspection, and new Flutter screens; re-run live checks after redeploying Round 3 to Antideploy.)*

## Remaining Boundaries

- Paid AI remains `AI_PROVIDER=disabled` while the Antideploy wallet is ₹0 (see [AI_SETUP.md](AI_SETUP.md)).
- Email-address-change double confirmation and background push/crawl workers are not implemented.
- Native release APK/IPA signing, production load testing, and cloud backup restore drills remain separate operational tasks.
