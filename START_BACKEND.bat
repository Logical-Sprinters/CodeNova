@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 start_backend.py
) else (
  python start_backend.py
)
if errorlevel 1 (
  echo.
  echo Backend did not start. Read the error above. Python 3.11+ and internet are required for first setup.
  pause
)
endlocal
