# BrandGuard - set up and prove the database on Windows, WITHOUT Docker.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\dev-native.ps1
#
# Use this if Docker is not installed. It talks to a locally installed
# PostgreSQL 16 (winget install -e --id PostgreSQL.PostgreSQL.16).
#
# What it does:
#   1. finds psql.exe
#   2. creates the 'brandguard' role and database if they do not exist
#   3. applies 001_schema.sql -> 002_functions.sql -> 003_seed.sql
#   4. runs the 28 schema assertions
#
# It is idempotent: running it twice changes nothing and proves the same thing.

param(
    [string]$SuperUser = "postgres",
    [string]$PsqlPath  = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

function Write-Step ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Stop-With ($m) { Write-Host "    $m" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- find psql
if (-not $PsqlPath) {
    $cmd = Get-Command psql -ErrorAction SilentlyContinue
    if ($cmd) { $PsqlPath = $cmd.Source }
}
if (-not $PsqlPath) {
    # The installer does not always add PostgreSQL to PATH. Look where it lands.
    $candidates = Get-ChildItem "$env:ProgramFiles\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
                  Sort-Object FullName -Descending
    if ($candidates) { $PsqlPath = $candidates[0].FullName }
}
if (-not $PsqlPath -or -not (Test-Path $PsqlPath)) {
    Stop-With ("psql.exe not found. Install PostgreSQL 16 first:  winget install -e --id PostgreSQL.PostgreSQL.16`n" +
               "    Then open a NEW terminal (PATH changes need one) and run this again.")
}
Write-Step "using $PsqlPath"

# ---------------------------------------------------------------- admin step
Write-Host ""
Write-Host "The 'postgres' superuser password is needed once, to create the app's role" -ForegroundColor Yellow
Write-Host "and database. It was set when you installed PostgreSQL." -ForegroundColor Yellow
$secure = Read-Host -AsSecureString "postgres password"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if (-not $adminPassword) { Stop-With "no password entered" }

Write-Step "checking the connection to PostgreSQL"
$env:PGPASSWORD = $adminPassword
& $PsqlPath -U $SuperUser -d postgres -tAc "SELECT 1" *> $null
if ($LASTEXITCODE -ne 0) {
    Stop-With ("cannot connect as '$SuperUser'. Is the PostgreSQL service running?`n" +
               "    Check: Get-Service *postgres*`n" +
               "    Start:  Start-Service postgresql-x64-16")
}

Write-Step "creating role 'brandguard' and database 'brandguard' (skipped if they exist)"
# A DO block needs dollar quoting, which collides with PowerShell here-strings.
# Single-quoted PowerShell strings keep the dollars literal, which is what we want.
$roleSql = @'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'brandguard') THEN
    CREATE ROLE brandguard LOGIN PASSWORD 'brandguard';
  END IF;
END
$$;
'@
$roleFile = Join-Path $env:TEMP "bg_role.sql"
[IO.File]::WriteAllText($roleFile, $roleSql, (New-Object System.Text.UTF8Encoding $false))
& $PsqlPath -U $SuperUser -d postgres -v ON_ERROR_STOP=1 -q -f $roleFile
if ($LASTEXITCODE -ne 0) { Stop-With "could not create the role" }

$dbExists = & $PsqlPath -U $SuperUser -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='brandguard'"
if ($dbExists -notmatch "1") {
    & $PsqlPath -U $SuperUser -d postgres -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE brandguard OWNER brandguard"
    if ($LASTEXITCODE -ne 0) { Stop-With "could not create the database" }
    Write-Host "    created"
} else {
    Write-Host "    already present"
}

# ------------------------------------------------------- app role from here on
$env:PGPASSWORD = "brandguard"

Write-Step "applying schema, functions and seed"
foreach ($file in @("database\001_schema.sql", "database\002_functions.sql", "database\003_seed.sql")) {
    if (-not (Test-Path $file)) { Stop-With "$file is missing - are you in the repository root?" }
    & $PsqlPath -U brandguard -d brandguard -v ON_ERROR_STOP=1 -q -f $file
    if ($LASTEXITCODE -ne 0) { Stop-With "$file failed to apply. Nothing after this point is trustworthy." }
    Write-Host "    $file"
}

Write-Step "running 28 schema assertions"
& $PsqlPath -U brandguard -d brandguard -v ON_ERROR_STOP=1 -q -f database\tests\001_assertions.sql
if ($LASTEXITCODE -ne 0) { Stop-With "assertions FAILED - do not build on top of this database." }

$env:PGPASSWORD = $null
Write-Host ""
Write-Host "Database is ready and proven (native PostgreSQL, no Docker)." -ForegroundColor Green
Write-Host ""
Write-Host "Next, in two more terminals:"
Write-Host "    .\scripts\api.ps1          # the API on http://localhost:8000"
Write-Host "    python scripts\smoke.py    # the 14-step end-to-end story"
Write-Host "    cd frontend; flutter run -d chrome"
Write-Host ""
Write-Host "Note: docker-compose.yml is simply unused on this path. Nothing else changes."
Write-Host ""
