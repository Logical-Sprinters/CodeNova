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

## 1 · Database — one command

```powershell
cd C:\path\to\BrandGuard
.\scripts\dev.ps1
```

That starts PostgreSQL, applies `001_schema.sql` → `002_functions.sql` → `003_seed.sql`,
then runs the 28 assertions. Expect `28 of 28 passed`.

**Why a script and not four pasted commands:** PowerShell 5.1 does not support `&&`, and
`psql` is usually not on PATH on Windows. The script uses `docker compose cp` to move each
file into the container, which also avoids a subtler trap — PowerShell re-encodes text piped
into a native command, and `003_seed.sql` contains curly quotes and an em dash that would
arrive as mojibake.

If you would rather see every step, this is exactly what it runs:

```powershell
docker compose up -d

for ($i = 0; $i -lt 90; $i++) {
  docker compose exec -T db pg_isready -U brandguard -d brandguard *> $null
  if ($LASTEXITCODE -eq 0) { break }
  Start-Sleep -Seconds 1
}

foreach ($f in @("database\001_schema.sql","database\002_functions.sql","database\003_seed.sql")) {
  docker compose cp $f db:/tmp/apply.sql
  docker compose exec -T db psql -U brandguard -d brandguard -v ON_ERROR_STOP=1 -q -f /tmp/apply.sql
}

docker compose cp database\tests\001_assertions.sql db:/tmp/assert.sql
docker compose exec -T db psql -U brandguard -d brandguard -v ON_ERROR_STOP=1 -q -f /tmp/assert.sql
```

If `docker compose cp` is unavailable in your Compose version, substitute
`docker cp database\001_schema.sql brandguard-db:/tmp/apply.sql`.

## 2 · API — one command

```powershell
.\scripts\api.ps1
```

Creates `.venv` on first run, installs `requirements.txt`, starts uvicorn. Check
`http://localhost:8000/health` — it returns row counts, so a green response proves the
database is reachable **and** populated. Interactive docs: `http://localhost:8000/docs`.

By hand, if you prefer:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1     # blocked? Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000
```

## 3 · The app

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

## 4 · Prove the whole story

With the API still running:

```powershell
python scripts\smoke.py
```

14 steps, ending with an approval being voided by a one-word edit.

## 5 · Reset to a clean state

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
| `psql: command not found` | client not installed | nothing to install: step 1 runs psql inside the container |
| `&& is not a valid statement separator` | PowerShell 5.1, not 7 | run one command per line, or use `.\scripts\dev.ps1` |
| `make: command not found` | `make` is not installed on Windows | use the `.ps1` scripts; `make` is the macOS/Linux path |
| `Activate.ps1 cannot be loaded` | execution policy | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| `python` opens the Microsoft Store | Windows app alias, no Python | install Python 3.12, or use `py -3` |
| `flutter run` complains about Android licences | first run on this machine | `flutter doctor --android-licenses` |
| port 5432 already in use | another Postgres | stop it, or change the port in `docker-compose.yml` and `.env` |
| CORS error in Chrome | request went to a different origin | the API allows `*` for the prototype; check the base URL first |
