# BrandGuard — fixed mobile app se start karein

## Android login/signup fix — pehle app rebuild karein

Native default ab **https://brandguard-app.antideploy.app** hai, local `10.0.2.2`
nahi. Purane project ke bajay **is release ke `mobile/`** se run karein:

```sh
cd mobile
flutter clean
flutter pub get --enforce-lockfile
flutter run
```

Windows: root ka **RUN_MOBILE.bat**. Selected server screen par dikhna chahiye.
Old IDE `API_BASE` local override remove karein. Phone par internet chahiye, laptop
backend nahi. Old installed app ZIP extract karne se update nahi hoti.
Full instructions: [LOGIN_FIX.md](LOGIN_FIX.md).

Cloud login ke liye real registered email/password use karein. Public
`creator@brandguard.demo` / `Demo@12345` local-demo credentials hain, cloud login nahi.


## Public hosted URL

**https://brandguard-app.antideploy.app**

Phone ya desktop browser mein kholein. Yeh Arena's temporary Live Preview nahi hai;
app Antideploy par hosted hai. Laptop par local backend chalana zaroori nahi.
Free hosting idle hone par first request ko wake-up mein thoda waqt lag sakta hai.

## Sign in

- Pehle diye private Creator/Reviewer evaluation logins isi live URL par kaam karte hain.
- Unka app aur private Storage access **17 November 2026, 01:30:31 IST** par expire hoga.
  Expiry silently extend nahi ki gayi. These are evaluation accounts, not permanent owners.
- Apne normal account ke liye **Create account** → email confirmation → Sign In.
- **Forgot password?** se real reset email aata hai. Link par naya password set karke
  app mein sign in karein. Reused/expired recovery links cannot reset the password.
- New signup is Creator. Permanent Reviewer/Admin access needs trusted assignment;
  public registration cannot self-promote.

Hosting account Google sign-in and BrandGuard app email/password sign-in are separate.
Test confirmation/reset emails connected owner's Gmail plus aliases par bheje gaye;
those temporary validation accounts were deleted. Ignore their now-used test links.

## Workflow

Creator → New Brand Check → brand and exact editor text → run check → inspect findings
and receipt. Save/reopen Drafts if needed. Uploads stay private; insert extracted text
into the editor if it should be scanned. Sign out in Profile. Reviewer → Review Queue
→ inspect exact text → approve or reject. A clean scan is not automatic human approval.

Rules, guidelines, verified fact sources, drafts, files, decisions and in-app
notifications use the real existing BrandGuard Supabase project. No replacement
project was created and LiFE Mitra Gujarat was not changed.

## AI ka remaining step

AI integration/key is prepared, but the Antideploy wallet has **₹0**, so paid AI is
currently **disabled**, not faked. Rule-based checks and human review still work.
Owner can add credit at https://antideploy.com/settings/billing#add-money .
**15% fee:** ₹100 AI wallet credit costs ₹115. No top-up/payment was made by the agent.
After funding, enable the existing OpenRouter integration and run live quality tests;
no second API key is needed. Details: [DEPLOYMENT.md](DEPLOYMENT.md).

## Current mobile-fix verification

**113 backend tests · 75 Flutter tests · clean analyzer · 13 native Dart/live HTTPS
checks**, including real Creator/Reviewer sign-ins, dashboard, logout and denied
reuse. Updated web bundle rebuilt. No Android APK/device test is claimed.
Evidence: `validation/login-fix/`.

## Previous hosted-deployment verification (historical)

113 backend tests · 49 Flutter tests · clean analyzer · 55 live public API workflow
checks · 17 real auth-email/callback/recovery checks · both rendered mobile-sized
role logins. Provider reported **5/5 test messages delivered**; this is not a claim
that a human opened the mailbox. Automatic and full Antideploy scans found no issues;
that is not an independent penetration-test certification.

Native mobile source remains `mobile/`. Hosted HTTPS now works without API_BASE;
explicit overrides remain for local development. Earlier ready-demo ZIP and source releases are preserved unchanged.
