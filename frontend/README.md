# `frontend/` Flutter application

This directory contains a separate Flutter app/prototype with its own responsive shell, features, models and API configuration. It is not the same client as `mobile/brandguard/`.

## Which app is active for this development?

For the BrandGuard FastAPI integration work documented in this branch, use **`mobile/brandguard/`**. See [AI Handoff](../docs/AI_HANDOFF.md).

Do not assume routes, API configuration, state, or screen behavior in this folder match the mobile client. If the team consolidates clients, record that decision and update both READMEs.

## Run this Flutter app

```bash
flutter pub get
flutter run -d chrome
flutter analyze
```

Inspect this app's own source/configuration before changing its API integration.
