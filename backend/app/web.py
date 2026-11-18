"""Optional same-origin Flutter-web + API host; native Flutter remains the main app.

First build mobile/ with `flutter build web --no-web-resources-cdn`, then from
backend/: `uvicorn app.web:app --host 0.0.0.0 --port 8000 --workers 1`.
Only static build assets are served; backend/.env and other server files are not.
"""

import os
from pathlib import Path

from fastapi.routing import APIRoute
from fastapi.staticfiles import StaticFiles

from app.config import BACKEND_DIR
from app.main import app

bundled = BACKEND_DIR.parent / "browser_preview"
default_web = (
    bundled
    if (bundled / "index.html").is_file()
    else BACKEND_DIR.parent / "mobile/build/web"
)
web_root = Path(os.environ.get("BRANDGUARD_WEB_DIR", str(default_web))).resolve()
if not (web_root / "index.html").is_file():
    raise RuntimeError(
        "Build mobile/ with flutter build web first, or set BRANDGUARD_WEB_DIR to its web output."
    )

# API routes take priority. Replace only the JSON landing page with the Flutter app.
app.router.routes[:] = [
    route
    for route in app.router.routes
    if not (isinstance(route, APIRoute) and route.path == "/" and route.name == "root")
]
app.mount("/", StaticFiles(directory=web_root, html=True), name="mobile-web")
