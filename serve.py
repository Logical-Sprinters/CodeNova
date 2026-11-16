"""Production entrypoint: platform PORT, same-origin Flutter UI + FastAPI.

No migrations/reseeding or service-account provisioning is run here. Existing
Supabase PostgreSQL/Auth/Storage are preserved. Runtime never falls back to demos.
"""

import os
from pathlib import Path
import sys


def main():
    backend = Path(__file__).resolve().parent / "backend"
    sys.path.insert(0, str(backend))
    os.chdir(backend)
    os.environ.setdefault("BRANDGUARD_DATA_DIR", "/tmp/brandguard")
    os.environ.setdefault("SEED_DEMO_USERS", "false")
    from app import config

    if config.AUTH_PROVIDER != "supabase" or config.SEED_DEMO_USERS:
        raise RuntimeError(
            "Production deployment requires Supabase Auth with demo seeding disabled"
        )
    import uvicorn

    uvicorn.run(
        "app.web:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8080")),
        workers=1,
        access_log=False,  # Auth verification links can carry secrets in query strings.
    )


if __name__ == "__main__":
    main()
