"""CSP for the self-hosted Flutter renderer and the two tiny auth callbacks.

Known inline auth scripts are hash-allowed, not blanket unsafe-inline. Flutter's
CanvasKit needs WebAssembly compilation and blob workers, not arbitrary JS eval.
Swagger/ReDoc remain developer documentation and get a separate CDN allowlist.
"""

import base64
import hashlib
import re

from app.routers.recovery import PAGE, CONFIRM_PAGE

_SCRIPT_HASHES = " ".join(
    "'sha256-"
    + base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
    + "'"
    for page in (PAGE, CONFIRM_PAGE)
    for script in re.findall(r"<script>(.*?)</script>", page, re.DOTALL)
)
CONTENT_SECURITY_POLICY = (
    "default-src 'self'; "
    "script-src 'self' 'wasm-unsafe-eval' blob: " + _SCRIPT_HASHES + "; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob:; font-src 'self' data:; "
    "connect-src 'self' blob:; worker-src 'self' blob:; "
    "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
)
DOCUMENTATION_SECURITY_POLICY = (
    "default-src 'self'; "
    "script-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; "
    "style-src 'self' https://cdn.jsdelivr.net https://fonts.googleapis.com 'unsafe-inline'; "
    "font-src 'self' https://fonts.gstatic.com data:; "
    "img-src 'self' https://fastapi.tiangolo.com data:; "
    "connect-src 'self'; object-src 'none'; base-uri 'self'; "
    "form-action 'self'; frame-ancestors 'none'"
)
