# Run it locally — Windows / PowerShell

Copy-paste, in order. Nothing here needs an admin shell except installing Docker and Flutter.

## 0 · Prerequisites, once

```powershell
winget install Docker.DockerDesktop
git --version
flutter --version      # if missing: https://docs.flutter.dev/get-started/install/windows
```

Start Docker Desktop and wait for the whale to stop animating. On Windows this is the
slowest step of the whole project, so do it first.

## 1 · Database

```powershell
cd C:\path\to\BrandGuard
docker compose up -d
$env:DATABASE_URL = "postgresql://brandguard:brandguard@localhost:5432/brandguard"

psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f database/001_schema.sql
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f database/002_functions.sql
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f database/003_seed.sql
```

No `psql` on PATH? Use the container's client instead:

```powershell
Get-Content database\001_schema.sql | docker compose exec -T db psql -U brandguard -d brandguard -v ON_ERROR_STOP=1
Get-Content database\002_functions.sql | docker compose exec -T db psql -U brandguard -d brandguard -v ON_ERROR_STOP=1
Get-Content database\003_seed.sql      | docker compose exec -T db psql -U brandguard -d brandguard -v ON_ERROR_STOP=1
```

## 2 · Prove the schema before building on it

```powershell
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f database/tests/001_assertions.sql
```

Expect 28 lines of `ok` and `28 of 28 passed`. If this fails, stop here.

## 3 · API

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000
```

Check `http://localhost:8000/health` — it returns row counts, so a green response proves the
database is reachable **and** populated. Interactive docs: `http://localhost:8000/docs`.

## 4 · The app

In a second terminal:

```powershell
cd frontend
flutter pub get
flutter run -d chrome          # fastest to check it works
flutter run                    # then pick an emulator or a plugged-in phone
```

A real phone on the same Wi-Fi:

```powershell
flutter run --dart-define=API_BASE=http://192.168.1.20:8000
```

An Android emulator needs nothing: `lib/core/api.dart` resolves `10.0.2.2` automatically,
because `localhost` inside the emulator is the emulator.

## 5 · Prove the whole story

With the API still running:

```powershell
python scripts\smoke.py
```

14 steps, ending with an approval being voided by a one-word edit.

## 6 · Reset to a clean state

```powershell
docker compose down -v
docker compose up -d
# then repeat step 1
```

`down -v` deletes the volume. Do it before any demo you care about, and never during one.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `docker compose up` hangs | WSL2 still starting | wait, or `wsl --update`, then retry |
| app shows "Cannot reach the API at …" | API not running, or wrong base URL | start `make api`; on a device pass `--dart-define=API_BASE=…` |
| `psql: command not found` | client not installed | use the container form in step 1 |
| `flutter run` complains about Android licences | first run on this machine | `flutter doctor --android-licenses` |
| port 5432 already in use | another Postgres | stop it, or change the port in `docker-compose.yml` and `.env` |
| CORS error in Chrome | request went to a different origin | the API allows `*` for the prototype; check the base URL first |
