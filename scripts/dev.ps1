# BrandGuard - set up and prove the database on Windows.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\dev.ps1
#   (or just: .\scripts\dev.ps1  once execution policy allows it)
#
# Needs Docker Desktop running. Does NOT need make, psql, or PowerShell 7.
# Every path is handled inside the container, so nothing has to be on PATH.

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

function Write-Step ($message) { Write-Host "==> $message" -ForegroundColor Cyan }
function Stop-With ($message)  { Write-Host "    $message" -ForegroundColor Red; exit 1 }

Write-Step "checking Docker"
docker version *> $null
if ($LASTEXITCODE -ne 0) { Stop-With "Docker is not responding. Start Docker Desktop and wait for it to finish starting." }

Write-Step "starting PostgreSQL"
docker compose up -d
if ($LASTEXITCODE -ne 0) { Stop-With "docker compose up failed. Run it alone to see the error." }

Write-Host -NoNewline "    waiting for PostgreSQL"
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    docker compose exec -T db pg_isready -U brandguard -d brandguard *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 1
}
Write-Host ""
if (-not $ready) { Stop-With "PostgreSQL was not ready after 90 seconds. Try: docker compose logs db" }

# The SQL is copied into the container rather than piped into it. PowerShell 5.1
# re-encodes text when it pipes to a native command, and 003_seed.sql contains
# curly quotes and an em dash that would arrive as mojibake.
Write-Step "applying schema, functions and seed"
$files = @(
    "database\001_schema.sql",
    "database\002_functions.sql",
    "database\003_seed.sql"
)
foreach ($file in $files) {
    docker compose cp $file "db:/tmp/apply.sql"
    if ($LASTEXITCODE -ne 0) { Stop-With "could not copy $file into the container" }

    docker compose exec -T db psql -U brandguard -d brandguard -v ON_ERROR_STOP=1 -q -f /tmp/apply.sql
    if ($LASTEXITCODE -ne 0) { Stop-With "$file failed to apply. Nothing after this point is trustworthy." }
    Write-Host "    $file"
}

Write-Step "running 28 schema assertions"
docker compose cp "database\tests\001_assertions.sql" "db:/tmp/assertions.sql"
if ($LASTEXITCODE -ne 0) { Stop-With "could not copy the assertion file into the container" }

docker compose exec -T db psql -U brandguard -d brandguard -v ON_ERROR_STOP=1 -q -f /tmp/assertions.sql
if ($LASTEXITCODE -ne 0) { Stop-With "assertions FAILED - do not build on top of this database." }

Write-Host ""
Write-Host "Database is ready and proven." -ForegroundColor Green
Write-Host ""
Write-Host "Next, in two more terminals:"
Write-Host "    .\scripts\api.ps1          # the API on http://localhost:8000"
Write-Host "    python scripts\smoke.py    # the 14-step end-to-end story"
Write-Host "    cd frontend; flutter run -d chrome"
Write-Host ""
