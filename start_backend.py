"""Run with `py start_backend.py` (Windows) or `python3 start_backend.py`.

Creates an isolated backend/.venv, installs the pinned runtime and starts Uvicorn.
No shell activation or working-directory guesswork is required.
"""

import argparse
import os
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time
from urllib.request import urlopen
import venv
import webbrowser


def _open_when_ready(url):
    for _ in range(120):
        try:
            with urlopen(url + "/health", timeout=1) as response:
                if response.status == 200:
                    webbrowser.open(url)
                    return
        except OSError:
            pass
        time.sleep(0.5)


def main():
    if sys.version_info < (3, 11):
        print("ERROR: Install Python 3.11 or newer, then run this launcher again.")
        return 1
    parser = argparse.ArgumentParser(description="Start the BrandGuard development API")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--web", action="store_true", help="Open bundled browser app")
    parser.add_argument(
        "--no-browser", action="store_true", help="Do not auto-open browser"
    )
    parser.add_argument(
        "--setup-only",
        action="store_true",
        help="Install dependencies without starting the server",
    )
    args = parser.parse_args()
    backend = Path(__file__).resolve().parent / "backend"
    environment = backend / ".venv"
    python = environment / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    try:
        if not python.exists():
            print("Creating backend/.venv ...", flush=True)
            venv.EnvBuilder(with_pip=True).create(environment)
        print("Checking/installing backend dependencies ...", flush=True)
        subprocess.run(
            [
                str(python),
                "-m",
                "pip",
                "install",
                "-r",
                str(backend / "requirements.txt"),
            ],
            check=True,
        )
        if args.setup_only:
            print("Backend setup complete.")
            return 0
        with socket.socket() as probe:
            try:
                probe.bind((args.host, args.port))
            except OSError:
                print(
                    f"ERROR: Port {args.port} is already in use. Stop the other server or use --port 8001."
                )
                return 1
        print(f"\nBrandGuard API: http://127.0.0.1:{args.port}/health", flush=True)
        print(f"API docs: http://127.0.0.1:{args.port}/docs", flush=True)
        print(
            "Keep this terminal open. Ctrl+C stops the development API.\n", flush=True
        )
        if args.web:
            print(f"Browser app: http://127.0.0.1:{args.port}/", flush=True)
            if not args.no_browser:
                threading.Thread(
                    target=_open_when_ready,
                    args=(f"http://127.0.0.1:{args.port}",),
                    daemon=True,
                ).start()
        return subprocess.call(
            [
                str(python),
                "-m",
                "uvicorn",
                "app.web:app" if args.web else "app.main:app",
                "--host",
                args.host,
                "--port",
                str(args.port),
                "--workers",
                "1",
            ],
            cwd=backend,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        print(
            f"ERROR: {error}\nCheck Python version, internet access and the package-install output above."
        )
        return 1
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
