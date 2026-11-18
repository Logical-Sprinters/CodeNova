#!/usr/bin/env sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/mobile"
if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK missing. Install Flutter 3.50.0 / Dart 3.14.0 and add flutter to PATH.' >&2
  exit 1
fi
flutter pub get --enforce-lockfile
exec flutter run --dart-define=API_BASE=https://brandguard-app.antideploy.app
