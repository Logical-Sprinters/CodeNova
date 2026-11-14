# BrandGuard - what is actually installed on this machine.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\check-env.ps1
#
# Prints one line per tool and the exact command to install anything missing.
# Run this first: it is faster than discovering each gap one failed command at a time.

$ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "BrandGuard environment check" -ForegroundColor Cyan
Write-Host "----------------------------"

function Test-Tool {
    param($Name, $Command, $Install, $Required)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) {
        $version = ""
        try { $version = (& $Command --version 2>&1 | Select-Object -First 1) } catch { }
        Write-Host ("  OK      {0,-10} {1}" -f $Name, $version) -ForegroundColor Green
        return $true
    }
    if ($Required) {
        Write-Host ("  MISSING {0,-10} {1}" -f $Name, $Install) -ForegroundColor Red
    } else {
        Write-Host ("  optional {0,-9} {1}" -f $Name, $Install) -ForegroundColor Yellow
    }
    return $false
}

Write-Host ""
Write-Host "Required for the database:" -ForegroundColor White
$docker = Test-Tool "docker" "docker" "winget install -e --id Docker.DockerDesktop   (or use the native PostgreSQL option below)" $false
$psql   = Test-Tool "psql"   "psql"   "winget install -e --id PostgreSQL.PostgreSQL.16   <- the no-Docker path" $false

if (-not $docker -and -not $psql) {
    Write-Host ""
    Write-Host "  Neither docker nor psql is installed." -ForegroundColor Red
    Write-Host "  Fastest fix (~2 minutes, no reboot):" -ForegroundColor Yellow
    Write-Host "      winget install -e --id PostgreSQL.PostgreSQL.16"
    Write-Host "  then open a NEW terminal and run .\scripts\dev-native.ps1"
    Write-Host ""
    Write-Host "  Docker Desktop also works but needs WSL2, virtualisation enabled in" -ForegroundColor Yellow
    Write-Host "  BIOS, and usually a reboot. Not worth it on a deadline."
}

Write-Host ""
Write-Host "Required for the API:" -ForegroundColor White
Test-Tool "python" "python" "winget install -e --id Python.Python.3.12   (or try: py -3)" $true | Out-Null
Test-Tool "git"    "git"    "winget install -e --id Git.Git" $true | Out-Null

Write-Host ""
Write-Host "Required for the app:" -ForegroundColor White
Test-Tool "flutter" "flutter" "https://docs.flutter.dev/get-started/install/windows  (then: flutter doctor)" $true | Out-Null

Write-Host ""
Write-Host "Optional:" -ForegroundColor White
Test-Tool "make"   "make"   "not needed on Windows - use the .ps1 scripts" $false | Out-Null
Test-Tool "gh"     "gh"     "winget install -e --id GitHub.cli" $false | Out-Null

Write-Host ""
Write-Host "Next:" -ForegroundColor Cyan
if ($docker) {
    Write-Host "  .\scripts\dev.ps1          # Docker path"
} elseif ($psql) {
    Write-Host "  .\scripts\dev-native.ps1   # installed PostgreSQL path"
} else {
    Write-Host "  install PostgreSQL 16 (see above), open a new terminal, then:"
    Write-Host "  .\scripts\dev-native.ps1"
}
Write-Host ""
