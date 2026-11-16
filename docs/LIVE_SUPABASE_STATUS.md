# BrandGuard — current hosted Supabase status

## Existing project preserved

| Item | Current state |
|---|---|
| Project | BrandGuard, `jtidayzktuzpjydshsva`, Mumbai `ap-south-1` |
| API | https://jtidayzktuzpjydshsva.supabase.co |
| Public app/API | https://brandguard-app.antideploy.app |
| Domain persistence | FastAPI → actual PostgreSQL, official CA + hostname `verify-full` |
| Auth | Email/password, signup and email confirmation enabled; JWT 1800s; refresh rotation retained |
| Storage | Existing private `brandguard-files`, 5 MB TXT/Markdown/PDF allowlist |
| Auth Site URL | https://brandguard-app.antideploy.app |
| Exact callback paths | `/auth/confirm` and `/auth/reset`, plus the existing allowed app root |
| Send Email Hook | Enabled: `[redacted: private account contact]` |
| Email transport | Signed Standard Webhooks request → provisioned Antideploy transactional relay |
| Auth/relay limits | Auth 20/hour; native relay 20 recipient-addresses/day |
| Runtime admin key | Not required and not in the deployed runtime |

LiFE Mitra Gujarat (`zaljyzpxcnrugmyjlhuc`) was not modified. No replacement project,
bucket, Auth provider or database was introduced by hosting. Existing migrations
20261115192757, 20261115192825 and 20261115195921 remain. Direct domain-table access
stays denied and private object owner/reviewer authorization is preserved.

## Actually verified

- Prior direct provider verification: 22 Auth/REST/Storage checks; TLS verification
  included a wrong-host rejection and a real process-restart persistence test.
- Current public hosted app: 55 API workflow checks, SQL read/rollback and safe cleanup.
- Current signed real email flow: 17 signup/confirmation/recovery/browser checks.
- Provider-reported test email delivery: 5/5 delivered, no bounce/complaint in snapshot.
- Normal runtime's actual SQL connection still uses TLS; no downgrade was made.

Current evidence: `../validation/antideploy/`. The latest public workflow read-back
run did not force a production restart; historical restart proof is not relabeled.
Callback links were reconstructed from the actual new private Auth token hashes for
automation, not read from a user's mailbox. Human mailbox opening is not claimed.

## Intended evaluation access

Two earlier evaluation users and their non-confidential sample document remain.
Their trusted `brandguard_access_until` flag is unchanged: app/private Storage access
expires **2026-11-16T20:00:31Z = 17 November 2026, 01:30:31 IST**. Restrictive Storage
policies and backend checks enforce it. Ordinary accounts without that flag have no
demo expiry. The evaluation logins are not permanent owner identities.

New public signup grants Creator. Reviewer/Admin must be assigned through trusted
`app_metadata`, never client-editable metadata. A permanent owner invite was not
silently provisioned. Test-created temporary accounts/objects/rows were removed.

## Remaining boundaries

AI key/integration is prepared but the wallet is ₹0, so paid AI is disabled and no
live model-quality/cost test is claimed. Email-address-change double confirmation
is not implemented by the app. Auth email is distinct from product/push notifications;
the latter remain in-app records. Native release/device certification, load testing
and a cloud backup/restore recovery drill are still separate tasks.

See [the deployment handoff](../DEPLOYMENT.md) before changing hosting, secrets,
email settings, roles or providers. Do not rerun project-creation/migration setup
against this existing live project, and never put private configuration into Flutter.
