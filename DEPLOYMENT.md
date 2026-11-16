# BrandGuard — live deployment handoff

> **Mobile 2.0.1+3 source update:** this ZIP fixes native default API selection and login UI; it does not redeploy or replace this existing hosted service. Latest source checks: 113 backend / 75 Flutter / 13 native HTTPS checks, analyzer clean. See [LOGIN_FIX.md](LOGIN_FIX.md) and [validation/RESULTS.md](validation/RESULTS.md). Counts below describe the previous deployment.

## Live links

- **App:** https://brandguard-app.antideploy.app
- **Health:** https://brandguard-app.antideploy.app/health
- **Antideploy dashboard:** https://antideploy.com/app/24f672f9-ef5a-4c45-8043-b98af546e6ad
- **Hosting account:** [redacted: hosting account email] — Google sign-in.
  This is the hosting account, not automatic Google sign-in inside BrandGuard.
- **Deployed source:** `BrandGuard-Antideploy/`; original releases preserved.

Yeh public hosted app hai, Arena preview ya laptop-only process nahi. Hosting remains
subject to the owner's Antideploy plan/account and provider availability; this is
not a promise of free hosting forever. Free hosting can sleep and take time to wake.

## Kya actually complete hua

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
| Regressions | **113 backend + 49 Flutter tests passed; analyzer clean** |
| Security | CSP/header finding fixed and redeployed; automatic and full platform scans have **0 findings** |
| Cleanup | All new temporary Auth users, objects and test-brand rows removed; intended demo/sample preserved |

Full scan report: https://antideploy.com/security/scan/ee8aaa4a-ac9c-4aff-90ae-b69298559f2d .
Security scans are useful checks, not a penetration-test or zero-vulnerability guarantee.
Flutter tests include mocks; the separate browser/live API checks above are real.
The public API run did not force an extra container restart or claim a new recovery drill.

For automated callback testing, the actual new one-use hashes were read privately
from this project's Auth database and the exact verification links opened in Chromium.
No mailbox access was used. Provider-reported delivery is not proof of human inbox
opening or spam-folder placement. No OTP/token/password/address was saved in public
evidence. Known auth scripts are CSP-hash allowed; URL fragments are erased and
callback tokens are not persisted in local/session storage. Optional platform-injected
external telemetry is deliberately blocked rather than weakening the app's CSP.

## Access — important

Earlier evaluation Creator/Reviewer credentials still work at the live URL. Their
app/private Storage access expires at **17 November 2026, 01:30:31 IST**
(`2026-11-16T20:00:31Z`). Expiry was preserved, not silently extended. These are not
permanent owner identities. No-expiry normal accounts are unaffected by that flag.

Use **Create account → confirm email → sign in** for a personal Creator account.
Public signup cannot grant Reviewer/Admin. A trusted administrator must grant that
role to the intended private identity. A permanent owner/reviewer invite was not
silently created. Hosting account Google login does not create a BrandGuard user.

The connected owner's Gmail/plus aliases received the test messages. Their temporary
accounts were removed and used test links should be ignored.

## AI — prepared, not funded/live-verified

One existing application-specific OpenRouter key is stored server-side by Antideploy.
Model: `openai/gpt-5.4-mini`; base URL: `https://openrouter.ai/api/v1`.
Strict JSON/evidence/quote/hash/span validation remains, with provider parameter
requirements and a request to deny provider data collection. These settings do not
constitute a legal zero-retention or truth guarantee.

**Wallet balance is ₹0; deployed `AI_PROVIDER=disabled`.** No paid inference,
model-quality claim or payment was made. Deterministic rules and human review work,
and the AI result explicitly abstains rather than inventing a factual pass.

Owner top-up link: https://antideploy.com/settings/billing#add-money .
**15% top-up fee: ₹100 credit costs ₹115.** Only the user can pay.
After funding, set `AI_PROVIDER=openrouter` in the same application's variables and
redeploy the same app. The existing `OPENROUTER_API_KEY`, base URL and model are
already provisioned/configured; **do not create another key**. Run matching,
contradictory and unsupported-claim tests against reviewer-verified facts before
calling live AI quality complete. Do not send confidential content without reviewing
provider terms and the organization's policy.

## Operational limits and maintenance

- Native email relay: **20 recipient-addresses per rolling day**, 10 messages/minute,
  at most 5 recipients/message. This app sends one recipient per auth email.
- Supabase auth-email throttle is 20/hour; the native relay's stricter 20/day cap
  still applies. Reaching a limit is an error, not fake send success or a retry loop.
- Site URL is the live app. Exact `/auth/confirm` and `/auth/reset` redirects are
  allowlisted. The signed hook lives at `/api/v1/auth/hooks/email`; unsigned calls
  are denied. Signup confirmation remains enabled.
- Normal runtime contains no Supabase admin/service-role key. Credentials live in
  encrypted host variables/private files, never Flutter, source archive or logs.
- Runtime changes need a new source upload; environment changes need redeploy.
  Follow https://antideploy.com/agent.md and reuse `.antideploy.json`'s app ID.
  Never create a duplicate app/project or overwrite native relay/AI variables.
- `serve.py` runs from `backend/` to resolve the bundled public CA; do not disable
  certificate/hostname verification. Local demo Auth is refused in production.
- Auth email supports signup/recovery/invite/magic-link, reauthentication and security
  notices. Email-address-change double confirmation is not implemented in the app.
- Human approval remains required. Storage/data are single-workspace, not a
  high-throughput, fully normalized multi-tenant system. No OCR/crawling/push worker.
- Native APK/IPA/device signing, production load testing and a cloud backup/restore
  recovery drill are not claimed complete.

Native Flutter uses the hosted API with:

```sh
cd mobile
flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
```

The earlier ready-demo ZIP stays unchanged and defaults to local SQLite without its
private environment. It is not this deployment's secret configuration or a new APK.
Sanitized current results are in `validation/antideploy/` and `validation/RESULTS.md`.
