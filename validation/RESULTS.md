# Validation — mobile login-fix source release

## Current executed checks — mobile 2.0.1+3

| Check | Result | Evidence in `login-fix/` |
|---|---|---|
| Backend regression/security/provider suite | **113 passed**, one nonfatal existing Starlette/httpx warning | `backend-tests.txt` |
| Flutter unit/widget tests | **75 passed**; 49 existing plus 26 new connection/UI regressions | `flutter-tests.txt` |
| Flutter analyzer | **No issues found** | `flutter-analyze.txt` |
| Native Dart HTTPS + hosted auth | **13 passed**, normal certificate verification, both roles' login/me/dashboard/logout/denial; config/health; safe signup reachability | `native-https-results.json` |
| Updated optional web bundle | **Release build successful**; bundled local CanvasKit assets; no service worker | `flutter-web-build.txt`, `web-bundle-results.json` |
| Rebuilt rendered UI + actual hosted API | **Creator + Reviewer passed**, 430×932, actual dashboard 200 and fresh-session logout | `rebuilt-browser-results.json` |

Screenshot cause: emulator-only `10.0.2.2:8000` was the Android default. Native now
uses the existing hosted HTTPS backend by default; web stays same-origin and local
API_BASE overrides remain explicit. No auth bypass or cloud reconfiguration.

Tests cover native endpoint selection across Android/iOS/desktop, explicit overrides,
invalid URLs, network/timeout handling, complete-response timeout, fail-closed demo
UI, live-config retry, no stored password, email validation and signup-confirmation
notice. Refresh/token/logout protections from the existing suite still pass.

Native HTTPS probes ran in the Dart VM using `ApiConfig.resolveBaseUrl`, not a
built Android APK. They logged out only their own newly created sessions. The
signup reachability probe was deliberately invalid (role forbidden, HTTP 422),
so it created no user and consumed no confirmation-email quota. No new end-to-end
signup/email/recovery mail run is claimed; the earlier verification is below.

The rebuilt-browser smoke served local release assets and used a test-only same-origin
route bridge to the real hosted API. It did not replace API responses with fake
user sessions, create users or send mail. Its temporary static server was stopped.
No production-CSP/device certification is implied by this local harness.

Existing hosted runtime, evaluation expiry, Supabase roles/data and previous ZIPs
are unchanged. The rebuilt bundle in this ZIP is newer than the still-live hosted
UI; this request did not redeploy the production service. No APK/IPA/native device,
paid AI, load test or independent security certification is claimed.

Inherited hosting-account contact metadata is redacted in this public source copy;
verification results and runtime configuration are unchanged.

## Previous executed checks — Antideploy deployed release (historical)

| Check | Result | Evidence in `antideploy/` |
|---|---|---|
| Backend regression/security/provider contracts | **113 passed**, one nonfatal Starlette/httpx deprecation warning | `backend-tests.txt` |
| Flutter unit/widget tests | **49 passed** on the earlier deployed source | `flutter-tests.txt` |
| Flutter analyzer | **No issues found** | `flutter-analyze.txt` |
| Public FastAPI → existing Supabase | **55 passed** | `cloud-workflow-results.json` |
| Rendered Chromium mobile-sized login | Creator + Reviewer **passed**, 430×932, actual dashboard APIs 200 | `public-browser-results.json`, `public-*-mobile.png` |
| Real signup/recovery/one-use callbacks | **17 passed**, Chromium, old password denied/new accepted | `auth-email-browser-results.json` |
| Relay delivery reports | **5 sent / 5 delivered**, zero bounce/complaint in snapshot | `email-deliverability-final.json`, `email-activity-final.json` |
| Automatic Antideploy security check | **0 findings** after CSP/header correction | `deployment-summary.json` |
| Full Antideploy endpoint/security check | **0 findings**, no scan charge | `full-security-results.json` |
| Production SQL/cleanup/retention | TLS active, no temporary test users/brand rows, intended demo/sample retained | `final-cleanup-and-provider-status.json` |
| Source-upload boundary | 203 files, 18,885,140 uncompressed bytes; no private `.env` or real keys in source | `source-upload-checks.json` |

App: https://brandguard-app.antideploy.app . The source bundle was below the
29,360,128-byte limit. Deployment is a non-root custom Docker container with dynamic
platform port and same-origin Flutter assets. Documentation/evidence added after the
runtime upload does not require another paid/quota-counting runtime release.

## What the separate live checks establish

The 55 public API checks cover trusted roles, forgery denial, library management,
verified source text, private upload/extraction/download, cross-user denial, draft
revisions/conflicts, deterministic scans and explicit AI abstention, human decisions,
exact-content approval validity, rule/version invalidation, private analytics/history,
notifications, SQL persistence/rollback, refresh/logout and password changes. They use
isolated temporary identities; only their own data is deleted. This public run did
not force a new container restart. Earlier cloud evidence includes an actual local
API process stop/restart and 22 direct provider + two strict-TLS checks.

Email acceptance really issued signup and recovery requests through Supabase's signed
production hook and the provisioned relay. The actual newly generated token hashes
were privately read for browser automation; no mailbox access or human message opening
is claimed. Confirmation/reset pages erase auth fragments and do not persist tokens.
The old password fails, new password works, logout denies reuse and a consumed reset
link cannot be reused. Provider-reported delivery is not a statistical inbox-placement
or uptime guarantee (only five test messages).

The two rendered role-login checks use real pointer/keyboard input in the bundled
CanvasKit UI and actual HTTP responses. Screenshots were visually inspected. These
are scoped browser smokes, not every screen/device's full end-to-end test. Auth pages
were separately executed with the production CSP active. An optional external
platform telemetry beacon was intentionally blocked; required application resources
had no CSP violations. No unsafe-eval exception was added for automation.

An initial validation-harness launch used the wrong local working directory for its
relative CA; its partial test rows/accounts/object were explicitly removed and a
correct full run passed. It was not a production TLS failure. Early browser harness
wait/semantics issues were corrected; final evidence above is the successful rerun.

## Deliberate limits / not claimed

- **Funded/live AI inference and model quality:** not tested; wallet ₹0, AI disabled.
  AI contract tests are mocked and do not prove provider access, truth or costs.
- Native APK/IPA/device/signing and every UI's E2E are not certified.
- No production load test, independent penetration-test certification, legal data
  residency/zero-retention certification or cloud backup/restore recovery drill.
- No embeddings/OCR/crawler/push worker/multi-tenant isolation feature was added.
- Public signup remains Creator-only. Permanent owner/reviewer provisioning is a
  trusted explicit action; evaluation expiry remains 17 November 2026, 01:30:31 IST.

Earlier `cloud/` and inherited local-demo logs are preserved as historical evidence,
not relabeled as new Antideploy runs. Older delivered ZIPs were not rewritten.
