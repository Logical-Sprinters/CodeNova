@echo off
setlocal
cd /d "%~dp0mobile"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter SDK was not found. Install Flutter 3.50.0 / Dart 3.14.0 and add flutter to PATH.
  pause
  exit /b 1
)
call flutter pub get --enforce-lockfile
if errorlevel 1 goto failed
call flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
if errorlevel 1 goto failed
exit /b 0
:failed
echo.
echo Mobile app did not start. Read the error above and LOGIN_FIX.md.
echo Make sure the phone/emulator is connected and selected by flutter devices.
pause
exit /b 1
