# First run, in order, stopping at the first failure.
#   .\scripts\dev.ps1
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not $env:DATABASE_URL) {
    $env:DATABASE_URL = "postgresql://brandguard:brandguard@localhost:5432/brandguard"
}

Write-Host "==> starting postgres" -ForegroundColor Cyan
docker compose up -d
for ($i = 0; $i -lt 60; $i++) {
    docker compose exec -T db pg_isready -U brandguard -d brandguard *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "    ready"; break }
    Start-Sleep -Seconds 1
}

Write-Host "==> applying schema, functions, seed" -ForegroundColor Cyan
foreach ($file in @("database/001_schema.sql", "database/002_functions.sql", "database/003_seed.sql")) {
    psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -q -f $file
    if ($LASTEXITCODE -ne 0) { throw "failed on $file" }
    Write-Host "    $file"
}

Write-Host "==> assertions" -ForegroundColor Cyan
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -q -f database/tests/001_assertions.sql
if ($LASTEXITCODE -ne 0) { throw "assertions failed" }

Write-Host ""
Write-Host "Database is ready. Now, in two terminals:" -ForegroundColor Green
Write-Host "    make api        (or: cd backend; python -m uvicorn app.main:app --reload)"
Write-Host "    make app-web    (or: cd frontend; flutter run -d chrome)"
Write-Host "Then: python scripts/smoke.py"
