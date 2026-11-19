@echo off
setlocal
cd /d "%~dp0\backend"

if exist ".venv\Scripts\python.exe" (
  ".venv\Scripts\python.exe" manage.py configure-ai
  goto :done
)
where py >nul 2>nul
if not errorlevel 1 (
  py -3 manage.py configure-ai
  goto :done
)
if exist "%LocalAppData%\Programs\Python\Python313\python.exe" (
  "%LocalAppData%\Programs\Python\Python313\python.exe" manage.py configure-ai
  goto :done
)
python manage.py configure-ai

:done
echo.
if errorlevel 1 (
  echo AI setup did not complete cleanly. Read the message above.
) else (
  echo Restart START_BACKEND.bat (or uvicorn) if the backend was already running.
)
pause
endlocal
