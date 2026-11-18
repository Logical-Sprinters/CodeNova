@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 start_backend.py --web --host 127.0.0.1
) else (
  python start_backend.py --web --host 127.0.0.1
)
if errorlevel 1 (
  echo.
  echo App did not start. Python 3.11+ and internet are needed for first dependency setup.
  pause
)
endlocal
