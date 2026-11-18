# Mobile 2.0.1+3 login-fix verification

- Backend regression suite: **113 passed** (one existing nonfatal deprecation warning).
- Flutter regression suite: **75 passed**, including 26 new connection/UI checks.
- Flutter analyzer: **No issues found**; changed Dart files formatted.
- The 19 connection/config tests also passed with a compiled custom API_BASE override.
- Native Dart HTTPS: **13 passed**, both existing roles login/me/dashboard/logout/token denial,
  normal TLS verification, live health/config and safe invalid-role signup reachability.
- Rebuilt 430×932 rendered web UI: both real role logins and dashboard APIs passed;
  test-only local asset server plus real hosted API route bridge, not a new production deploy.
- Updated web bundle uses local generic + Chromium CanvasKit and no service worker registration.

`flutter-tests.txt` is the successful serialized run (`--concurrency=1`). An initial
parallel test-compiler run exited unexpectedly in the constrained workspace; no test
assertion was suppressed. The full suite then passed and the source analyzer is clean.

The safe signup probe returned 422 for a forbidden role. It did not create a user or
send email. Earlier real signup/email/recovery verification is historical evidence in
`../antideploy/`, not relabeled as a new mail run. Private probe scripts, credentials,
request bodies, tokens and the local-bridge screenshot are intentionally not included.

This is a source ZIP, not a signed APK/IPA. No Android/iOS physical-device test, paid AI
inference, load test or independent penetration-test certification is claimed. Existing
hosted runtime/data, roles, evaluation expiry and earlier source ZIPs remain unchanged.
