> **Superseded by Round 3 (v3.0.0):** This document describes the earlier `2.0.1` native connection fix (`113` backend / `75` Flutter baseline). See [README.md](README.md) and [START_HERE.md](START_HERE.md) for current Round 3 features, tests, and setup.

# BrandGuard 2.0.1 — mobile login / signup connection fix

## Problem kya tha?

Screenshot mein Android app `http://10.0.2.2:8000` call kar rahi thi. `10.0.2.2`
Android emulator se computer ke local backend tak ka special address hai; normal
physical phone ke liye public backend address nahi. Wahan server reachable nahi
tha, isliye login aur signup dono network timeout de rahe the.

## Is release mein fix

- Native Android/iOS/desktop default: **https://brandguard-app.antideploy.app**.
- `flutter run` ke liye ab `API_BASE` define zaroori nahi. Local backend automatic
  default nahi raha; local development ke liye explicit override available hai.
- Screen par selected server address aur connection state dikhti hai.
- Cloud/offline state mein public local-demo credentials show/autofill nahi hote.
- Connection errors short/actionable hain; raw SocketException/ports ka dump nahi.
- Retry connection, email/password validation aur clear confirmation-success notice.
- No auth bypass, fixed password, fake session, role elevation or disabled TLS.

## IMPORTANT: old installed app ko rebuild karna hoga

Sirf ZIP download/extract se phone par installed old application update nahi hoti.
Purani project directory ki jagah **is project ke `mobile/`** se run karein.

```sh
cd mobile
flutter clean
flutter pub get --enforce-lockfile
flutter run
```

Windows par root ka `RUN_MOBILE.bat` use kar sakte hain. Woh hosted URL explicitly
pass karta hai. Android Studio / VS Code ke purane run arguments mein
`API_BASE=http://10.0.2.2:8000` ho toh remove karein. Sirf hot reload mat karein;
app fully stop karke rebuild/run karein. Tested source toolchain Flutter 3.50.0 /
Dart 3.14.0 hai; source Dart `^3.14.0` require karta hai.

Correct screen par server **brandguard-app.antideploy.app** aur connected state dikhni
chahiye. Phone par internet on rakhein. Backend laptop par run karna zaroori nahi.
If an old installation conflicts with a newly signed local build, uninstall that
old debug app and run again; unsaved local state will be cleared.

## Login / signup

Apna real registered cloud email/password use karein. Naya user: Create account →
apna accessible email → confirmation email open → Sign In. `creator@brandguard.demo`
and `reviewer@brandguard.demo` **local demo only** hain, live cloud credentials nahi.
Unke public `Demo@12345` password se hosted app login nahi karegi.

Earlier private evaluation users had app/Storage expiry **17 November 2026, 01:30:31 IST**
(now expired). Normal confirmed accounts without that flag are not time-limited.
Reviewer/Admin permissions still require trusted assignment.

## Explicit local development only

```sh
# Android emulator, with a real local API already running on your computer:
flutter run --dart-define=API_BASE=http://10.0.2.2:8000

# A physical phone needs the computer's reachable LAN IP, not 10.0.2.2:
flutter run --dart-define=API_BASE=http://YOUR_COMPUTER_LAN_IP:8000
```

The optional browser bundle stays same-origin, so `OPEN_APP.bat` can still run an
isolated local SQLite/demo browser app. That is intentionally separate from native
mobile's default hosted Supabase connection.

## Verification and boundaries

Historical `2.0.1` checks are in `validation/login-fix/`.
