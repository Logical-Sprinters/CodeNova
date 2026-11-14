# BrandGuard - run the API on Windows.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\api.ps1
#
# Creates the virtual environment on first run, installs requirements, and starts
# uvicorn. No make, no activation step to remember.

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
Set-Location backend

if (-not (Test-Path ".venv")) {
    Write-Host "==> creating virtual environment" -ForegroundColor Cyan
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { Write-Host "    python not found - try 'py -3 -m venv .venv'" -ForegroundColor Red; exit 1 }
    .\.venv\Scripts\python.exe -m pip install --upgrade pip --quiet
    .\.venv\Scripts\python.exe -m pip install -r requirements.txt --quiet
    if ($LASTEXITCODE -ne 0) { Write-Host "    dependency install failed" -ForegroundColor Red; exit 1 }
}

Write-Host "==> http://localhost:8000/docs   (Ctrl+C to stop)" -ForegroundColor Green
$env:PYTHONPATH = "."
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
